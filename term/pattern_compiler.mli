(******************************************************************************)
(*  _  __ * The Kappa Language                                                *)
(* | |/ / * Copyright 2010-2019 CNRS - Harvard Medical School - INRIA - IRIF  *)
(* | ' /  *********************************************************************)
(* | . \  * This file is distributed under the terms of the                   *)
(* |_|\_\ * GNU Lesser General Public License Version 3                       *)
(******************************************************************************)

(** Kappa pattern compiler *)

val connected_components_sum_of_ambiguous_mixture :
  debugMode:bool -> compileModeOn:bool -> Contact_map.t -> Pattern.Env.t ->
  ?origin:Operator.rev_dep -> LKappa.rule_mixture ->
  Pattern.Env.t *
  ((Pattern.id * Pattern.cc) array *
   Instantiation.abstract Instantiation.test list list) list

val connected_components_sum_of_ambiguous_rule :
  debugMode:bool -> compileModeOn:bool -> Contact_map.t -> Pattern.Env.t ->
  ?origin:Operator.rev_dep -> LKappa.rule_mixture -> Raw_mixture.t ->
  (Operator.rev_dep option * (Pattern.id * Pattern.cc) array *
     (Instantiation.abstract Instantiation.event) *
       (Instantiation.abstract Primitives.Transformation.t list *
          Instantiation.abstract Primitives.Transformation.t list))
    list * (Pattern.Env.t * Operator.rev_dep option)

val lkappa_of_elementary_rule :
  Signature.s -> Pattern.Env.t -> Primitives.elementary_rule ->
  LKappa.rule_mixture * Raw_mixture.t
  (** @Return: [(r_mix,r_create)] *)
