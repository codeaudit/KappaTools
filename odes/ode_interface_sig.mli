(** Network/ODE generation
  * Creation: 22/07/2016
  * Last modification: Time-stamp: <Apr 11 2017>
*)

module type Interface =
sig
  type compil
  type cache

  type mixture              (* not necessarily connected, fully specified *)
  type chemical_species     (* connected, fully specified *)
  type canonic_species      (* chemical species in canonic form *)
  type pattern              (* not necessarity connected, maybe partially specified *)
  type connected_component  (* connected, maybe partially specified *)

  type rule
  (*type hidden_init*)

  type init =
    ((connected_component array list,int) Alg_expr.e * rule
     * Locality.t) list

  val empty_cache: compil -> cache

  val get_init: compil -> init

  val mixture_of_init: compil -> rule(*hidden_init*) -> mixture

  val dummy_chemical_species: compil -> chemical_species

  val compare_connected_component :
    connected_component -> connected_component -> int

  val print_connected_component :
    ?compil:compil -> Format.formatter -> connected_component -> unit

  val print_token :
    ?compil:compil -> Format.formatter -> int -> unit

  val print_chemical_species:
    ?agent_sep:(Format.formatter -> unit)
    -> ?compil:compil -> Format.formatter -> chemical_species -> unit

  val print_canonic_species:
    ?agent_sep:(Format.formatter -> unit)
    -> ?compil:compil -> Format.formatter -> canonic_species -> unit

  val rate_convention: compil ->
    Remanent_parameters_sig.rate_convention
  val what_do_we_count: compil -> Ode_args.count
  val do_we_count_in_embeddings: compil -> bool
  val do_we_prompt_reactions: compil -> bool

  val nbr_automorphisms_in_chemical_species: chemical_species -> int

  val canonic_form: chemical_species -> canonic_species

  val connected_components_of_patterns:
    pattern -> connected_component list

  val connected_components_of_mixture:
    compil -> cache ->
    mixture -> cache  * chemical_species list

  type embedding (* the domain is connected *)

  type embedding_forest (* the domain may be not connected *)

  val lift_embedding: embedding -> embedding_forest

  val find_embeddings:
    compil -> connected_component -> chemical_species ->
    embedding list

  val find_embeddings_unary_binary:
    compil -> pattern -> chemical_species -> embedding_forest list

  val disjoint_union:
    compil  ->
    (connected_component * embedding * chemical_species) list ->
    pattern * embedding_forest * mixture

  (*type rule*)

  type rule_name = string

  type rule_id = int

  type rule_id_with_mode =
    rule_id * Rule_modes.arity * Rule_modes.direction

  val valid_modes: compil -> rule -> rule_id -> rule_id_with_mode list

  val lhs: compil -> rule_id_with_mode -> rule -> pattern

  val token_vector:
    rule ->
    ((connected_component array list,int) Alg_expr.e Locality.annot
     * int) list

  val token_vector_of_init:
    rule ->
    ((connected_component array list,int) Alg_expr.e Locality.annot
     * int) list

  val print_rule_id: Format.formatter -> rule_id -> unit

  val print_rule:
    ?compil:compil -> Format.formatter -> rule -> unit

  val print_rule_name:
    ?compil:compil -> Format.formatter -> rule -> unit

  val string_of_var_id:
    ?compil:compil -> ?init_mode:bool -> Loggers.t -> int -> string

  val rate:
    compil -> rule -> rule_id_with_mode ->
    (connected_component array list, int) Alg_expr.e Locality.annot option

  val rate_name:
    compil -> rule -> rule_id_with_mode -> rule_name

  val apply: compil -> rule -> embedding_forest -> mixture -> mixture

  val lift_species: compil -> chemical_species -> mixture

  val get_compil:
    rate_convention:Remanent_parameters_sig.rate_convention ->
    show_reactions:bool -> count:Ode_args.count ->
    compute_jacobian:bool -> Run_cli_args.t -> compil

  val get_rules: compil -> rule list

  val get_variables:
    compil ->
    (string *
     (connected_component array list,int) Alg_expr.e Locality.annot)
      array

  val get_obs:
    compil -> (connected_component array list,int) Alg_expr.e list

  val get_obs_titles: compil -> string list

  val nb_tokens: compil -> int

  (*symmetries for initial states*)

  val divide_rule_rate_by: cache -> compil -> rule ->
    cache * int

  val species_of_initial_state_env  :
    Model.t ->
    Contact_map.t ->
    Pattern.PreEnv.t ->
    ('b * Primitives.elementary_rule * 'c) list ->
    Pattern.PreEnv.t * Pattern.cc list

  val species_of_initial_state : compil ->
    cache ->
    ('b * Primitives.elementary_rule * 'c) list ->
    cache * Pattern.cc list

  val detect_symmetries :
  Remanent_parameters_sig.parameters ->
  compil ->
  cache ->
  chemical_species list ->
  (*(string *
   (connected_component array list,int) Alg_expr.e Locality.annot)
    array ->*)
  (string list * (string * string) list) Mods.StringMap.t
    Mods.StringMap.t -> cache * Symmetries.symmetries


  val print_symmetries:
  Remanent_parameters_sig.parameters ->
  compil -> Symmetries.symmetries -> unit

  val get_rule_cache: cache -> LKappa_auto.cache
  val set_rule_cache: LKappa_auto.cache -> cache -> cache

  val get_representative:
    Remanent_parameters_sig.parameters ->
    compil -> cache -> Symmetries.reduction ->
    chemical_species -> cache * chemical_species

  val bwd_interpretation:
    Remanent_parameters_sig.parameters ->
    Symmetries.bwd_map -> Symmetries.reduction -> chemical_species ->
    Symmetries.class_description option

  val fold_bwd_map:
  (chemical_species -> Symmetries.class_description -> 'a -> 'a) ->
  Symmetries.bwd_map ->
  'a -> 'a

  val class_representative:
    Symmetries.class_description -> chemical_species

  val add_equiv_class:
    Remanent_parameters_sig.parameters ->
    compil ->
    cache ->
    Symmetries.reduction ->
    Symmetries.bwd_map ->
    chemical_species ->
    cache *
    Symmetries.bwd_map


end
