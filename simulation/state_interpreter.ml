(******************************************************************************)
(*  _  __ * The Kappa Language                                                *)
(* | |/ / * Copyright 2010-2017 CNRS - Harvard Medical School - INRIA - IRIF  *)
(* | ' /  *********************************************************************)
(* | . \  * This file is distributed under the terms of the                   *)
(* |_|\_\ * GNU Lesser General Public License Version 3                       *)
(******************************************************************************)

type t = {
  init_stopping_times : (Nbr.t * int) list;
  mutable stopping_times : (Nbr.t * int) list;
  perturbations_alive : bool array;
  time_dependent_perts : int list;
  mutable force_test_perturbations : int list;
  perturbations_not_done_yet : bool array;
  (* internal array for perturbate function (global to avoid useless alloc) *)
  mutable flux: (Data.din_data) list;
  with_delta_activities : bool;
}

let compare_stops (t1,p1) (t2,p2) =
  let t = Nbr.compare t1 t2 in
  if t = 0 then compare p1 p2 else t

let empty ~with_delta_activities env =
  let stopping_times =
    let algs_deps = Model.all_dependencies env in
    Model.fold_perturbations
      (fun i acc x ->
         match x.Primitives.alarm with
         | Some n -> (n,i)::acc
         | None ->
           let () =
             if (Alg_expr.is_equality_test_time
                   algs_deps (fst x.Primitives.precondition)) then
               raise
                 (ExceptionDefn.Malformed_Decl
                    ("Equality test on time requires an alarm",
                     (snd x.Primitives.precondition)))
           in
           let () =
             if (Alg_expr.is_equality_test_time
                   algs_deps (fst x.Primitives.repeat)) then
               raise
                 (ExceptionDefn.Malformed_Decl
                    ("Equality test on time requires an alarm",
                     (snd x.Primitives.repeat))) in
           acc)
      [] env in
  let stops = List.sort compare_stops stopping_times in
  let time_dependent_perts =
    let rec aux dep acc =
      Operator.DepSet.fold
        (fun dep perts ->
           match dep with
           | Operator.ALG j ->
             aux (Model.get_alg_reverse_dependencies env j) perts
           | Operator.MODIF p ->
             List_util.merge_uniq Mods.int_compare [p] perts
           | Operator.RULE _ -> perts)
    dep acc in
    aux (let x,_,_,_ = Model.all_dependencies env in x) [] in
  {
    init_stopping_times = stops;
    stopping_times = stops;
    perturbations_alive =
      Array.make (Model.nb_perturbations env) true;
    force_test_perturbations = [];
    time_dependent_perts;
    perturbations_not_done_yet =
      Array.make (Model.nb_perturbations env) true;
    flux = [];
    with_delta_activities;
  }

let observables_values env graph counter =
  Model.map_observables
    (Rule_interpreter.value_alg counter graph)
    env

let do_modification ~outputs env counter graph state extra modification =
  let print_expr_val =
    Kappa_printer.print_expr_val
      (Rule_interpreter.value_alg counter graph) in
  match modification with
  | Primitives.ITER_RULE ((v,_),r) ->
    let text =
      Format.asprintf
        "@[<h>%a@]" (Kappa_printer.modification ~env) modification in
    let graph' =
      Nbr.maybe_iteri
        (fun _ g ->
           Rule_interpreter.force_rule
             ~outputs env counter g (Trace.PERT text) r)
        graph (Rule_interpreter.value_alg counter graph v) in
    let graph'',extra' =
      Rule_interpreter.update_outdated_activities
        (fun _ _ _  -> ()) env counter graph' extra in
    ((false,graph'',state), extra')
  | Primitives.UPDATE (i,(expr,_)) ->
    let graph' = Rule_interpreter.overwrite_var i counter graph expr in
    let graph'',extra' =
        Rule_interpreter.update_outdated_activities
          (fun _ _ _  -> ()) env counter graph' extra in
    ((false, graph'', state), extra')
  | Primitives.STOP pexpr ->
    let () = if pexpr <> [] then
        let file = Format.asprintf "@[<h>%a@]" print_expr_val pexpr in
        outputs (Data.Snapshot
                   (Rule_interpreter.snapshot env counter file graph)) in
    ((true,graph,state),extra)
  | Primitives.PRINT (pe_file,pe_expr) ->
    let file_opt =
      match pe_file with
        [] -> None
      | _ -> Some (Format.asprintf "@[<h>%a@]" print_expr_val pe_file)
    in
    let line = Format.asprintf "@[<h>%a@]" print_expr_val pe_expr in
    let () = outputs
        (Data.Print
           {Data.file_line_name = file_opt ; Data.file_line_text = line;}) in
    ((false, graph, state),extra)
  | Primitives.PLOTENTRY ->
    let () = outputs (Data.Plot (observables_values env graph counter)) in
    ((false, graph, state),extra)
  | Primitives.SNAPSHOT pexpr  ->
    let file =
      if pexpr = [] then "snap.ka"
      else Format.asprintf "@[<h>%a@]" print_expr_val pexpr in
    let () = outputs (Data.Snapshot
                        (Rule_interpreter.snapshot env counter file graph)) in
    ((false, graph, state),extra)
  | Primitives.CFLOW (name,cc,tests) ->
    let name = match name with
      | Some s -> s
      | None ->
        let domain = Model.domain env in
        Format.asprintf
          "@[<h>%a@]"
          (Pp.array Pp.comma (fun _ -> Pattern.print ~domain ~with_id:false))
          cc in
    ((false,
      Rule_interpreter.add_tracked ~outputs cc name tests graph,
      state),
     extra)
  | Primitives.CFLOWOFF (name,cc) ->
    ((false, Rule_interpreter.remove_tracked cc name graph, state),extra)
  | Primitives.SPECIES_OFF fn ->
    let file = Format.asprintf "@[<h>%a@]" print_expr_val fn in
    ((false, Rule_interpreter.remove_tracked_species file graph, state),extra)
  | Primitives.DIN (rel,s) ->
    let file = Format.asprintf "@[<h>%a@]" print_expr_val s in
    let () =
      if List.exists
          (fun x -> Fluxmap.flux_has_name file x && x.Data.din_kind = rel)
          state.flux
      then outputs
          (Data.Warning
             (None,
              fun f ->
                Format.fprintf
                  f "At t=%f, e=%i: tracking DIN into \"%s\" was already on"
                  (Counter.current_time counter)
                  (Counter.current_event counter) file)) in
    let () = state.flux <-
        Fluxmap.create_flux env counter rel file::state.flux in
    ((false, graph, state),extra)
  | Primitives.DINOFF s ->
    let file = Format.asprintf "@[<h>%a@]" print_expr_val s in
    let (these,others) =
      List.partition (Fluxmap.flux_has_name file) state.flux in
    let () = List.iter
        (fun x -> outputs (Data.DIN (Fluxmap.stop_flux env counter x)))
        these in
    let () = state.flux <- others in
    ((false, graph, state),extra)
  | Primitives.SPECIES (s,cc,tests) ->
    let file = Format.asprintf "@[<h>%a@]" print_expr_val s in
    ((false,
      Rule_interpreter.add_tracked_species cc file tests graph,
      state),
     extra)

let rec perturbate ~outputs ~is_alarm env counter graph state = function
  | [] -> (false,graph,state)
  | i :: tail ->
    let pert = Model.get_perturbation env i in
    let mod_alarm = match pert.Primitives.alarm with
      | None -> true
      | Some _ -> is_alarm in
    if state.perturbations_alive.(i) &&
       state.perturbations_not_done_yet.(i) &&
       Rule_interpreter.value_bool
         counter graph (fst pert.Primitives.precondition) &&
         mod_alarm
    then
      let (stop,graph,state as acc,tail') =
        List.fold_left (fun ((stop,graph,state),extra as acc) effect ->
            if stop then acc else
              do_modification ~outputs env counter graph state extra effect)
          ((false,graph,state),tail) pert.Primitives.effect in
      let () = state.perturbations_not_done_yet.(i) <- false in
      let alive =
        Rule_interpreter.value_bool
           counter graph (fst pert.Primitives.repeat) in
      let () = if alive&&(pert.Primitives.alarm = None) then
          state.force_test_perturbations <- i::state.force_test_perturbations in
      let () = state.perturbations_alive.(i) <- alive in
      if stop then acc else
        perturbate ~outputs ~is_alarm:false env counter graph state tail'
    else
      perturbate ~outputs ~is_alarm:false env counter graph state tail

let do_modifications ~outputs env counter graph state list =
  let (stop,graph,state as acc,extra) =
    List.fold_left (fun ((stop,graph,state),extra as acc) effect ->
        if stop then acc else
          do_modification ~outputs env counter graph state extra effect)
      ((false,graph,state),[]) list in
  if stop then acc
  else perturbate ~outputs ~is_alarm:false env counter graph state extra

let initialize ~bind ~return ~outputs env counter graph0 state0 init_l =
  let mgraph =
    List.fold_left
      (fun mstate (alg,compiled_rule) ->
         bind
           mstate
           (fun (stop,state,state0) ->
              let value =
                Rule_interpreter.value_alg counter state alg in
              let actions =
                compiled_rule.Primitives.instantiations.Instantiation.actions in
              let creations_sort =
                List.fold_left
                  (fun l -> function
                     | Instantiation.Create (x,_) ->
                       Matching.Agent.get_type x :: l
                     | Instantiation.Mod_internal _ | Instantiation.Bind _
                     | Instantiation.Bind_to _ | Instantiation.Free _
                     | Instantiation.Remove _ -> l) [] actions in
              return (stop,
                Nbr.iteri
                  (fun _ s ->
                     match Rule_interpreter.apply_given_rule
                             ~outputs env counter s (Trace.INIT creations_sort)
                             compiled_rule with
                     | Rule_interpreter.Success s -> s
                     | (Rule_interpreter.Clash | Rule_interpreter.Corrected
                       | Rule_interpreter.Blocked) ->
                       raise (ExceptionDefn.Internal_Error
                                (Locality.dummy_annot "Bugged initial rule")))
                  state value,state0))) (return (false,graph0,state0)) init_l in
  bind
    mgraph
    (fun (_,graph,state0) ->
       let mid_graph,_ =
         Rule_interpreter.update_outdated_activities
           (fun _ _ _  -> ()) env counter graph [] in
       let out =
         Tools.array_fold_lefti (fun i (stop,graph,state as acc) _ ->
             if stop then acc else
               perturbate
                 ~outputs ~is_alarm:true env counter graph state [i])
       (false,mid_graph,state0) state0.perturbations_alive in
       let () =
         Array.iteri (fun i _ -> state0.perturbations_not_done_yet.(i) <- true)
           state0.perturbations_not_done_yet in
       return out)

let one_rule ~outputs ~maxConsecutiveClash env counter graph state =
  let prev_activity = Rule_interpreter.activity graph in
  let act_stack = ref [] in
  let finalize_registration my_syntax_rd_id =
    match state.flux, state.with_delta_activities with
    | [], false -> ()
    | l, _ ->
      let () =
        if state.with_delta_activities then
          outputs (Data.DeltaActivities
                     (my_syntax_rd_id,!act_stack)) in
      let n_activity = Rule_interpreter.activity graph in
      let () =
        List.iter
          (fun fl ->
             let () = Fluxmap.incr_flux_hit my_syntax_rd_id fl in
             match fl.Data.din_kind with
             | Primitives.ABSOLUTE | Primitives.RELATIVE -> ()
             | Primitives.PROBABILITY ->
               List.iter
                 (fun (syntax_rd_id,(_,new_act)) ->
                    Fluxmap.incr_flux_flux
                      my_syntax_rd_id syntax_rd_id
                      (let cand = new_act /. n_activity in
                       match classify_float cand with
                       | (FP_nan | FP_infinite) ->
                         let () =
                           let ct = Counter.current_time counter in
                           outputs
                             (Data.Warning
                                (None,
                                 fun f -> Format.fprintf
                                     f "An infinite (or NaN) activity variation has been ignored at t=%f"
                                     ct)) in 0.
                       | (FP_zero | FP_normal | FP_subnormal) -> cand) fl)
                 !act_stack) l in
      act_stack := [] in
  (* let () = *)
  (*   Format.eprintf "%a@." (Rule_interpreter.print_injections env) graph in *)

  let applied_rid_syntax,final_step,graph' =
    Rule_interpreter.apply_rule ~outputs ~maxConsecutiveClash env counter graph in
  match applied_rid_syntax with
  | None -> (final_step,graph',state)
  | Some syntax_rid ->
    let register_new_activity syntax_rd_id old_act new_act =
      match state.flux, state.with_delta_activities with
      | [], false -> ()
      | l,_ ->
        let () = act_stack := (syntax_rd_id,(old_act,new_act))::!act_stack in
        List.iter
          (fun fl ->
             Fluxmap.incr_flux_flux syntax_rid syntax_rd_id
               (
                 let cand =
                   match fl.Data.din_kind with
                   | Primitives.ABSOLUTE -> new_act -. old_act
                   | Primitives.PROBABILITY ->
                     -. (old_act /. prev_activity)
                   | Primitives.RELATIVE ->
                     if (match classify_float old_act with
                         | (FP_zero | FP_nan | FP_infinite) -> false
                         | (FP_normal | FP_subnormal) -> true)
                     then (new_act -. old_act) /. old_act
                     else (new_act -. old_act) in
                 match classify_float cand with
                 | (FP_nan | FP_infinite) ->
                   let () =
                     let ct = Counter.current_time counter in
                     outputs
                       (Data.Warning
                          (None,
                           fun f -> Format.fprintf
                               f "An infinite (or NaN) activity variation has been ignored at t=%f"
                               ct)) in 0.
                 | (FP_zero | FP_normal | FP_subnormal) -> cand) fl)
          l in
    let force_tested = state.force_test_perturbations in
    let () = state.force_test_perturbations <- [] in
    let graph'',extra_pert =
      Rule_interpreter.update_outdated_activities
        register_new_activity env counter graph' force_tested in
    let () = finalize_registration syntax_rid in
    let (stop,graph''',state') =
      perturbate
        ~outputs ~is_alarm:false env counter graph'' state extra_pert in
    let () =
      Array.iteri (fun i _ -> state.perturbations_not_done_yet.(i) <- true)
        state.perturbations_not_done_yet in
    let () =
      if !Parameter.debugModeOn then
        Format.printf "@[<v>Obtained@ %a@]@." (Rule_interpreter.print env) graph''' in
    (final_step||stop,graph''',state')

let rec perturbate_until_first_backtrack
          env counter ~outputs (stop,graph,state,dt) =
  match state.stopping_times with
  | [] -> (stop,graph,state,dt,false)
  | (ti,pe) :: tail ->
     if (Nbr.is_smaller ti (Nbr.F (Counter.current_time counter +. dt))) then
       let pert = Model.get_perturbation env pe in
       if not(pert.Primitives.needs_backtrack) then
         let stop',graph',state',dt' =
           match Nbr.to_float
                   (Nbr.sub ti (Nbr.F (Counter.current_time counter))) with
           | None -> false,graph,state,dt
           | Some dti ->
              let dt' = dt -. dti in
              (*set time for perturbate *)
              if Counter.one_time_advance counter dti then
                let stop',graph',state' = perturbate
                    ~outputs ~is_alarm:true env counter graph state [pe] in
                let tail' = match pert.Primitives.alarm with
                  | None -> tail
                  | Some n ->
                    if state.perturbations_alive.(pe) then
                      List_util.merge_uniq compare_stops [((Nbr.add ti n),pe)] tail
                    else tail in
                let () = state.stopping_times <- tail' in
                let () = state'.perturbations_not_done_yet.(pe) <- true in
                (* Argument to reset only pe and not all perts is "if
                   you're not backtracking, nothing depends upon
                   you"... We'd better get sure of that :-) *)
                stop',graph',state',dt'
              else true, graph, state, dt' in

         perturbate_until_first_backtrack
           env counter ~outputs (stop',graph',state',dt')

       (* if some perturbation needs backtrack, return the perturbation *)
       else (stop,graph,state,dt,true)
     else (stop,graph,state,dt,false)

let perturbate_with_backtrack ~outputs env counter graph state = function
  | [] -> assert false
  | (ti,pe) :: tail ->
    let tail' = match (Model.get_perturbation env pe).Primitives.alarm with
      | None -> tail
      | Some n ->
        List_util.merge_uniq
          compare_stops [((Nbr.add ti n),pe)] tail in
    let () = state.stopping_times <- tail' in
    if Counter.one_time_correction_event counter ti then
      let () =
        let outputs counter' time =
          let cand =
            observables_values env graph (Counter.fake_time counter' time) in
          if Array.length cand > 1 then outputs (Data.Plot cand) in
        Counter.fill ~outputs counter ~dt:0. in
      let stop,graph',state' =
        perturbate ~outputs ~is_alarm:true env counter graph state [pe] in
      let () =
        Array.iteri (fun i _ -> state.perturbations_not_done_yet.(i) <- true)
          state.perturbations_not_done_yet in
      (stop,graph',state')
    else (true,graph,state)

let a_loop
    ~outputs ~dumpIfDeadlocked ~maxConsecutiveClash env counter graph state =
  let activity = Rule_interpreter.activity graph in
  let rd = Random.State.float (Rule_interpreter.get_random_state graph) 1.0 in
  let dt = abs_float (log rd /. activity) in

  let out =
    (*Activity is null or dt is infinite*)
    if not (activity > 0.) || dt = infinity then
      match state.stopping_times with
      | [] ->
        let () =
          if dumpIfDeadlocked then
            outputs
              (Data.Snapshot
                 (Rule_interpreter.snapshot env counter "deadlock.ka" graph)) in
        let () =
          outputs
            (Data.Warning
               (None,
                fun f ->
                  Format.fprintf f
                    "A deadlock was reached after %d events and %Es (Activity = %.5f)"
                    (Counter.current_event counter)
                    (Counter.current_time counter) activity)) in
        (true,graph,state)
      | l ->
        perturbate_with_backtrack ~outputs env counter graph state l

    else
      (*activity is positive*)
      match state.stopping_times with
      | (ti,_) :: _
        when Nbr.is_smaller ti (Nbr.F (Counter.current_time counter +. dt)) ->

         let (stop,graph',state',dt',needs_backtrack) =
           perturbate_until_first_backtrack
             env counter ~outputs (false,graph,state,dt) in

         begin
           if needs_backtrack then
             perturbate_with_backtrack
               ~outputs env counter graph' state' state'.stopping_times
           else
             (*set time for apply rule *)
             let () =
               let outputs counter' time =
                 let cand = observables_values
                     env graph' (Counter.fake_time counter' time) in
                 if Array.length cand > 1 then outputs (Data.Plot cand) in
               Counter.fill ~outputs counter ~dt:dt' in
              let continue = Counter.one_time_advance counter dt' in

              if (not continue) || stop then (true,graph',state') else
                one_rule ~outputs ~maxConsecutiveClash env counter graph' state'
         end

      | _ ->
        let () =
          let outputs counter' time =
            let cand =
              observables_values env graph (Counter.fake_time counter' time) in
            if Array.length cand > 1 then outputs (Data.Plot cand) in
          Counter.fill ~outputs counter ~dt in
        let continue = Counter.one_time_advance counter dt in
        let (stop,graph',state') = perturbate
            ~outputs ~is_alarm:false
            env counter graph state state.time_dependent_perts in
        if (not continue)||stop then (true,graph',state') else
          one_rule ~outputs ~maxConsecutiveClash env counter graph' state' in
  out

let end_of_simulation ~outputs env counter graph state =
  let () =
    let outputs counter' time =
      let cand =
        observables_values env graph (Counter.fake_time counter' time) in
      if Array.length cand > 1 then outputs (Data.Plot cand) in
    Counter.fill ~outputs counter ~dt:0. in
  List.iter
    (fun e ->
       let () =
         outputs
           (Data.Warning
              (None,
               fun f ->
                 Format.fprintf
                   f
                   "Tracking DIN into \"%s\" was not stopped before end of simulation"
                   (Fluxmap.get_flux_name e))) in
       outputs (Data.DIN (Fluxmap.stop_flux env counter e)))
    state.flux
