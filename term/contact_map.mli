(******************************************************************************)
(*  _  __ * The Kappa Language                                                *)
(* | |/ / * Copyright 2010-2017 CNRS - Harvard Medical School - INRIA - IRIF  *)
(* | ' /  *********************************************************************)
(* | . \  * This file is distributed under the terms of the                   *)
(* |_|\_\ * GNU Lesser General Public License Version 3                       *)
(******************************************************************************)

type t = (Mods.IntSet.t * Mods.Int2Set.t) array array
(** (internal_states, (agent_type, agent_site) link_states *)

val print_kappa : Signature.s -> Format.formatter -> t -> unit


val print_cycles : Signature.s -> Format.formatter -> t -> unit

val to_yojson : t -> Yojson.Basic.json
val of_yojson : Yojson.Basic.json -> t
