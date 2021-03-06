(**************************************************************************)
(*                                                                        *)
(*    Copyright 2012-2013 OCamlPro                                        *)
(*    Copyright 2012 INRIA                                                *)
(*                                                                        *)
(*  All rights reserved.This file is distributed under the terms of the   *)
(*  GNU Lesser General Public License version 3.0 with linking            *)
(*  exception.                                                            *)
(*                                                                        *)
(*  OPAM is distributed in the hope that it will be useful, but WITHOUT   *)
(*  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY    *)
(*  or FITNESS FOR A PARTICULAR PURPOSE.See the GNU General Public        *)
(*  License for more details.                                             *)
(*                                                                        *)
(**************************************************************************)

(** Cudf interface *)

open OpamTypes

(** Cudf sets *)
module Set: OpamMisc.SET with type elt = Cudf.package

(** Cudf maps *)
module Map: OpamMisc.MAP with type key = Cudf.package

(** Cudf graph *)
module Graph: sig
  (** Graph of cudf packages *)
  type t

  (** Build a graph from a CUDF universe *)
  val of_universe: Cudf.universe -> t

  (** Return the transitive closure of [g] *)
  val transitive_closure: t -> t

  (** Return the transitive closure of dependencies of [set],
      sorted in topological order. *)
  val close_and_linearize: t -> Set.t -> Cudf.package list
end

(** Difference between universes *)
module Diff: sig

  (** Differences between the versions of a given package *)
  type package = {
    installed  : Set.t;
    removed    : Set.t;
    reinstalled: Set.t;
  }

  (** Difference between universe *)
  type universe = (Cudf_types.pkgname, package) Hashtbl.t

  (** Computation of differences between universe *)
  val diff: Cudf.universe -> Cudf.universe -> universe

end

(** Cudf action graph *)
module ActionGraph: OpamActionGraph.SIG with type package = Cudf.package

(** Abstract type that may be returned in case of conflicts *)
type conflict

(** Return the transitive closure of dependencies of [set],
    sorted in topological order *)
val dependencies: Cudf.universe -> Cudf.package list -> Cudf.package list

(** Return the transitive closure of dependencies of [set],
    sorted in topological order *)
val reverse_dependencies: Cudf.universe -> Cudf.package list -> Cudf.package list

(** Check if a request is satisfiable and return the reasons why not unless
    [explain] is set to [false] *)
val check_request:
  ?explain:bool ->
  version_map:int OpamPackage.Map.t ->
  Cudf.universe ->
  Cudf_types.vpkg request ->
  (Cudf.universe, conflict) result

(** Compute the final universe state using the external solver. *)
val get_final_universe:
  version_map:int OpamPackage.Map.t ->
  Cudf.universe ->
  Cudf_types.vpkg request ->
  (Cudf.universe, conflict) result

(** Compute the list of actions to match the difference between two
    universe. Remark: the result order is unspecified, ie. need to use
    [atomic_actions] to get a solution which respects the
    topological order induced by dependencies. *)
val actions_of_diff: Diff.universe -> Cudf.package action list

exception Cyclic_actions of Cudf.package action list list

(** Computes the actions to process from a solution, from the actions
    obtained by a simple universe diff. The 'simple' universe
    should not contain build dependencies and will be used for resolution ;
    [complete_universe] should include build-deps, it's used to get the
    dependency ordering of actions.

    Returns a graph of atomic actions, i.e. only removals and installs. Use
    [reduce_actions] to reduce it to a graph including reinstall and
    up/down-grade actions.

    May raise [Cyclic_actions]. *)
val atomic_actions:
  simple_universe:Cudf.universe ->
  complete_universe:Cudf.universe ->
  Cudf.package action list ->
  ActionGraph.t

(** Heuristic to compute the likely cause of all actions in a graph from the set
    of packages passed in the original request. Assumes a reduced graph. *)
val compute_root_causes: ActionGraph.t -> OpamPackage.Name.Set.t ->
  Cudf.package cause Map.t

(** Resolve a CUDF request. The result is either a conflict holding
    an explanation of the error, or a resulting universe.
    [~extern] specifies whether the external solver should be used *)
val resolve:
  extern:bool ->
  version_map:int OpamPackage.Map.t ->
  Cudf.universe ->
  Cudf_types.vpkg request ->
  (Cudf.universe, conflict) result

(** Computes a list of actions to proceed from the result of [resolve].
    Note however than the action list is not yet complete: the transitive closure
    of reinstallations is not yet completed, as it requires to fold over the
    dependency graph in considering the optional dependencies.
    The first argument specifies a function that will be applied to the starting
    universe before computation: useful to re-add orphan packages. *)
val to_actions:
  (Cudf.universe -> Cudf.universe) ->
  Cudf.universe ->
  (Cudf.universe, conflict) result ->
  (Cudf.package action list, conflict) result

(** [remove universe name constr] Remove all the packages called
    [name] satisfying the constraints [constr] in the universe
    [universe]. *)
val remove: Cudf.universe -> Cudf_types.pkgname -> Cudf_types.constr -> Cudf.universe

(** Uninstall all the package in the universe. *)
val uninstall_all: Cudf.universe -> Cudf.universe

(** Install a package in the universe. We don't care about any
    invariant here (eg. the resulting universe can have mutliple
    versions of the same package installed). *)
val install: Cudf.universe -> Cudf.package -> Cudf.universe

(** Remove all the versions of a given package, but the one given as argument. *)
val remove_all_uninstalled_versions_but: Cudf.universe ->
  string -> Cudf_types.constr -> Cudf.universe

(** Cudf labels for package fields in the cudf format
    (use for the field Cudf.pkg_extra and with Cudf.lookup_package_property) *)
val s_source: string         (** the original OPAM package name (as string) *)
val s_source_number: string  (** the original OPAM package version (as string) *)
val s_reinstall: string      (** a package to be reinstalled (a bool) *)
val s_installed_root: string (** true if this package belongs to the roots
                                 ("installed manually") packages *)
val s_pinned: string         (** true if the package is pinned to this version *)

(** {2 Pretty-printing} *)

(** Convert a package constraint to something readable. *)
val string_of_vpkgs: Cudf_types.vpkg list -> string

val make_conflicts:
  version_map:int package_map -> Cudf.universe ->
  Algo.Diagnostic.diagnosis -> ('a, conflict) result
val cycle_conflict:
  version_map:int package_map -> Cudf.universe ->
  string list list -> ('a, conflict) result

(** Convert a conflict to something readable by the user. The first argument
    should return a string like "lwt<3.2.1 is not available because..." when called
    on an unavailable package (the reason can't be known this deep in the solver) *)
val string_of_conflict: (atom -> string) -> conflict -> string

(** Returns three lists of strings:
    - the final reasons why the request can't be satisfied
    - the dependency chains explaining it
    - the cycles in the actions to process (exclusive with the other two) *)
val strings_of_conflict:
  (atom -> string) -> conflict -> string list * string list * string list

(** Dumps the given cudf universe to the given channel *)
val dump_universe: out_channel -> Cudf.universe -> unit

(** Pretty-print atoms *)
val string_of_atom: Cudf_types.vpkg -> string

(** Pretty-print requests *)
val string_of_request: Cudf_types.vpkg request -> string

(** Pretty-print the universe *)
val string_of_universe: Cudf.universe -> string

(** Pretty-print of packages *)
val string_of_packages: Cudf.package list -> string

(** Convert a cudf package back to an OPAM package *)
val cudf2opam: Cudf.package -> package

(** Returns the list of packages in a Cudf universe *)
val packages: Cudf.universe -> Cudf.package list

(** {2 External solver} *)
val external_solver_available: unit -> bool

(** Runs a test to check the version of the optimisation criteria accepted by
    the external solver. Result is cached for subsequent queries. *)
val check_cudf_version: unit -> [`Compat | `Latest]

(** Converts an OPAM request to a Cudf request *)
val to_cudf: Cudf.universe -> Cudf_types.vpkg request
  -> Cudf.preamble * Cudf.universe * Cudf.request
