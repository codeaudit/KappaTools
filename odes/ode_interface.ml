(** Network/ODE generation
  * Creation: 22/07/2016
  * Last modification: Time-stamp: <Mar 23 2017>
*)

(*type contact_map = (int list * (int * int) list) array array*)

type rule = Primitives.elementary_rule

type compil =
  {
    contact_map: (int list * (int * int) list) array array ;
    environment: Model.t ;
    init: (Alg_expr.t * rule * Locality.t) list;
    rate_convention: Remanent_parameters_sig.rate_convention ;
    show_reactions: bool ;
    count: Ode_args.count ;
    compute_jacobian: bool
  }

type cc_cache = Pattern.PreEnv.t

type nauto_in_rules_cache = LKappa_auto.cache

type sym_cache = Symmetries.cache

type cache =
  {
    cc_cache: cc_cache ;
    rule_cache: nauto_in_rules_cache;
    representant_cache: sym_cache
  }

let get_representant parameters compil cache symmetries species =
  let rep_cache, rule_cache, cc_cache, species =
    Symmetries.representant
      ~parameters
      (Model.signatures compil.environment)
      cache.representant_cache
      cache.rule_cache
      cache.cc_cache
      symmetries species
  in
  {
    representant_cache = rep_cache;
    cc_cache = cc_cache ;
    rule_cache = rule_cache ;
  }, species

let get_cc_cache cache = cache.cc_cache

let set_cc_cache cc_cache cache = {cache with cc_cache = cc_cache}

let get_rule_cache cache = cache.rule_cache

let set_rule_cache rule_cache cache =
  {cache with rule_cache = rule_cache}

let get_sym_cache cache = cache.representant_cache

let set_sym_cache sym_cache cache =
  {cache with representant_cache = sym_cache}

(*type hidden_init = Primitives.elementary_rule*)

type init = (Alg_expr.t * rule * Locality.t) list

let get_init compil= compil.init

let lift_opt f compil_opt =
  match
    compil_opt
  with
  | None -> None
  | Some a -> Some (f a)

let contact_map compil = compil.contact_map

let environment compil = compil.environment

let domain compil = Model.domain (environment compil)

let domain_opt = lift_opt domain

let environment_opt = lift_opt environment

type mixture = Edges.t(* not necessarily connected, fully specified *)

type chemical_species = Pattern.cc
(* connected, fully specified *)

type canonic_species = chemical_species (* chemical species in canonic form *)

type pattern = Pattern.id array
(* not necessarity connected, maybe partially specified *)

type connected_component = Pattern.id
(* connected, maybe partially specified *)

let dummy_chemical_species compil =
  Pattern.empty_cc (Pattern.Env.signatures (domain compil))

let rate_convention compil = compil.rate_convention

let what_do_we_count compil = compil.count

let do_we_count_in_embeddings compil =
  match
    what_do_we_count compil
  with
  | Ode_args.Occurrences -> false
  | Ode_args.Embeddings -> true

let do_we_prompt_reactions compil =
  compil.show_reactions

let print_chemical_species ?compil f =
  Format.fprintf f "@[<h>%a@]"
    (Pattern.print_cc
       ~new_syntax:false
       ?sigs:(Option_util.map Model.signatures (environment_opt compil))
       ?cc_id:None ~with_id:false)

let print_token ?compil fmt k =
  Format.fprintf fmt
    "%a"
    (Model.print_token ?env:(environment_opt compil))
    k

let print_canonic_species = print_chemical_species

let nbr_automorphisms_in_chemical_species x =
  List.length (Pattern.automorphisms x)

let compare_connected_component = Pattern.compare_canonicals

let print_connected_component ?compil =
  Pattern.print ~new_syntax:false ?domain:(domain_opt compil) ~with_id:false

let canonic_form x = x

let connected_components_of_patterns = Array.to_list

let connected_components_of_mixture compil cache e =
  let cc_cache = cache.cc_cache in
  let contact_map = contact_map compil in
  let sigs = Pattern.Env.signatures (domain compil) in
  let cc_cache, acc =
    Symmetries.connected_components_of_mixture
      sigs cc_cache contact_map e
  in
  {cache with cc_cache = cc_cache}, acc

let species_of_initial_state compil cache list =
  let sigs = Model.signatures compil.environment in
  let contact_map = contact_map compil in
  let cc_cache, list =
    Symmetries.species_of_initial_state sigs
      contact_map list
  in
  {cache with cc_cache = cc_cache}, list

type embedding = Renaming.t (* the domain is connected *)
type embedding_forest = Matching.t
(* the domain may be not connected *)

let lift_embedding x =
  Option_util.unsome
    Matching.empty
    (Matching.add_cc Matching.empty 0 x)

let find_embeddings compil =
  Pattern.embeddings_to_fully_specified (domain compil)

(*let find_embeddings compil pattern species =
  let () =
    print_connected_component ~compil Format.std_formatter pattern
  in
  let () = Format.fprintf Format.std_formatter " into " in
  let () =
    print_chemical_species ~compil Format.std_formatter species
  in
  let l =
    find_embeddings compil pattern species
  in
  let () = Format.fprintf Format.std_formatter "? embeddings: %i \n" (List.length l) in
  l*)

let find_embeddings_unary_binary compil p x =
  Tools.array_fold_lefti
    (fun i acc cc ->
       let em = find_embeddings compil cc x in
       List_util.map_flatten
         (fun m ->
            List_util.map_option (fun r -> Matching.add_cc m i r) em)
         acc)
    [Matching.empty]
    p

let disjoint_union compil l =
  let sigs = Model.signatures (compil.environment) in
  Symmetries.disjoint_union sigs l

type rule_id = int

type arity = Rule_modes.arity

type direction = Rule_modes.direction

type rule_name = string

type rule_id_with_mode = rule_id * arity * direction

let lhs _compil _rule_id r = r.Primitives.connected_components

let add x y list  =
  match y with
  | None -> list
  | Some _ -> x::list

let mode_of_rule compil rule =
  let _env = environment compil in
  let _id = rule.Primitives.syntactic_rule in
  if (* Pierre, could you help me here please ? *)
    (* I would like to know if the rule comes from the interpretation of a rule in a direct way, or from the interpretation of a rule in a reverse way *)
    (* ex: 'A.B' A(x),B(x) <-> A(x!1),B(x!1) @ 1(2),3(4) *)
    (* I am expecting Direct for the rule A(x),B(x) -> A(x!1),B(x!1) @ 1(2) *)
    (* and Op for the rule A(x!1),B(x!1) -> A(x),B(x) @ 3(4) *)
    true
  then
    Rule_modes.Direct
  else
    Rule_modes.Op

let valid_modes compil rule id =
  let mode = mode_of_rule compil rule in
  List.rev_map
    (fun x -> id,x,mode)
    (List.rev
       (Rule_modes.Usual::
        (add Rule_modes.Unary rule.Primitives.unary_rate [])))

let rate _compil rule (_,arity,_) =
  match
    arity
  with
  | Rule_modes.Usual -> Some rule.Primitives.rate
  | Rule_modes.Unary -> Option_util.map fst rule.Primitives.unary_rate

let token_vector a = a.Primitives.delta_tokens

let token_vector_of_init = token_vector

let print_rule_id log = Format.fprintf log "%i"

let print_rule ?compil =
  Kappa_printer.elementary_rule ?env:(environment_opt compil)

let print_rule_name ?compil f r =
  let env = environment_opt compil in
  let id = r.Primitives.syntactic_rule in
  Model.print_ast_rule ?env f id

let string_of_var_id ?compil ?init_mode logger r =
  let f logger r =
    match Loggers.get_encoding_format logger with
    | Loggers.Mathematica | Loggers.Maple ->
      "var"^(string_of_int r)^(match init_mode with Some true -> "" | Some _ | None -> "(t)")
    | Loggers.Octave | Loggers.Matlab ->
      "var("^(string_of_int r)^")"
    | Loggers.TXT | Loggers.TXT_Tabular
    | Loggers.XLS | Loggers.SBML | Loggers.DOT
    | Loggers.HTML | Loggers.HTML_Graph | Loggers.HTML_Tabular
    | Loggers.Json | Loggers.Matrix -> ""
  in
  let env = environment_opt compil in
  match env with
  | None -> f logger r
  | Some env ->
    try
      let array = Model.get_algs env in
      fst (array.(r-1))
    with
      _ -> f logger r

let string_of_var_id_jac ?compil r dt =
  "jacvar("^(string_of_int r)^","^(string_of_int dt)^")"

let rate_name compil rule rule_id =
  let (_kade_id,arity,direction) = rule_id in
  let arity_tag =
    match arity with
    | Rule_modes.Usual -> ""
    | Rule_modes.Unary -> "(unary context)"
  in
  let direction_tag =
    match direction with
    | Rule_modes.Direct -> ""
    | Rule_modes.Op -> "(op)"
  in
  Format.asprintf "%a%s%s" (print_rule_name ~compil) rule
    arity_tag direction_tag

let apply compil rule inj_nodes mix =
  let sigs = Model.signatures compil.environment in
  Symmetries.apply sigs rule inj_nodes mix

let lift_species compil x =
  fst @@
  Pattern.add_fully_specified_to_graph
    (Model.signatures compil.environment)
    (Edges.empty ~with_connected_components:false) x

let get_rules compil =
  Model.fold_rules
    (fun _ acc r -> r::acc) [] (environment compil)

let get_variables compil = Model.get_algs (environment compil)

let get_obs compil =
  Array.to_list
    (Model.map_observables (fun r -> r) (environment compil))

let remove_escape_char =
  (* I do not know anything about it be single quote are not allowed in Octave, please correct this function if you are more knowledgeable *)
  String.map
    (function '\'' -> '|' | x -> x)

let get_obs_titles compil =
  let env = environment compil in
  Array.to_list @@
  Model.map_observables
    (fun x -> remove_escape_char
        (Format.asprintf "%a"
           (Kappa_printer.alg_expr ~env) x))
    env

let get_compil
    ~rate_convention  ~show_reactions ~count ~compute_jacobian cli_args =
  let (_,_,env, contact_map,  _, _, _, _, init), _ =
    Cli_init.get_compilation cli_args in
  {
    environment = env ;
    contact_map = contact_map ;
    init = init ;
    rate_convention = rate_convention ;
    show_reactions = show_reactions ;
    count = count ;
    compute_jacobian = compute_jacobian
  }

let empty_cc_cache compil =
  Pattern.PreEnv.of_env (Model.domain compil.environment)

let empty_lkappa_cache () = LKappa_auto.init_cache ()

let empty_sym_cache () = Symmetries.empty_cache ()

let empty_cache compil =
  {
    cc_cache  = empty_cc_cache compil ;
    rule_cache = empty_lkappa_cache () ;
    representant_cache = empty_sym_cache () ;
  }

let mixture_of_init compil c =
  let _, emb, m = disjoint_union compil [] in
  let m = apply compil c emb m in
  m

let nb_tokens compil = Model.nb_tokens (environment compil)

let divide_rule_rate_by cache compil rule =
  match compil.rate_convention with
  | Remanent_parameters_sig.Common -> assert false
(* this is not a valid parameterization *)
(* Common can be used only to compute normal forms *)
  | Remanent_parameters_sig.No_correction -> cache, 1
  | Remanent_parameters_sig.Biochemist
  | Remanent_parameters_sig.Divide_by_nbr_of_autos_in_lhs ->
    let rule_id = rule.Primitives.syntactic_rule in
    let lkappa_rule =
      Model.get_ast_rule compil.environment rule_id
    in
    let rule_cache, output =
      LKappa_auto.nauto compil.rate_convention cache.rule_cache
        lkappa_rule
    in
    {cache with rule_cache = rule_cache}, output

(****************************************************************)
(*cannonic form per rule*)

let return_cc_from_alg_expr compil =
  let env = compil.environment in
  let pair_array = get_variables compil in
  let pattern_cc_list =
    Array.fold_left (fun current_list (s, algs) ->
        (*pattern.id array list list*)
        let e = Alg_expr.extract_connected_components algs in
        let pattern_cc_array_list =
          List.fold_left (fun current_list1 array_list ->
              let array_list =
                List.fold_left (fun store_list value_array ->
                    let pattern_cc_list =
                      Array.fold_left (fun store_list_cc id ->
                          let point =
                            Pattern.Env.get (Model.domain env) id
                          in
                          let cc = Pattern.Env.content point in
                          cc :: store_list_cc
                        ) store_list value_array
                    in
                    List.append pattern_cc_list store_list
                  ) current_list1 array_list
              in
              List.append array_list current_list
            ) current_list e
        in
        List.append pattern_cc_array_list current_list
      ) [] pair_array
  in
  pattern_cc_list


let convert_cc_to_rule_mixture parameters compil =
  let sigs = Model.signatures compil.environment in
  let pattern_cc_list = return_cc_from_alg_expr compil in
  let r_mixture_list =
    List.fold_left (fun current_list cc ->
        let op =
          Raw_mixture_extra.pattern_to_mixture ~parameters
            sigs
            cc
        in
        match op with
        | None -> current_list
        | Some r_mixture ->
          r_mixture :: current_list
      ) [] pattern_cc_list
  in
  r_mixture_list

let detect_symmetries parameters compil cache
    chemical_species
    contact_map =
  let rule_cache = cache.rule_cache in
  let rule_cache, symmetries =
    Symmetries.detect_symmetries
      parameters
      compil.environment
      rule_cache
      compil.rate_convention
      chemical_species
      (get_rules compil)
      contact_map
  in
  {cache with rule_cache = rule_cache},
  symmetries


let print_symmetries parameters compil symmetries =
  let env = compil.environment in
  Symmetries.print_symmetries parameters env symmetries
