structure RedPrlSortData =
struct
  datatype param_sort =
     DIM
   | HYP
   | META_NAME
   | OPID

  and sort =
     EXP
   | TAC
   | MTAC
   | JDG
   | TRIV
   | MATCH_CLAUSE of sort
   | PARAM_EXP of param_sort
   | LVL
   | KIND

  val rec sortToString = 
    fn EXP => "exp"
     | TAC => "tac"
     | MTAC => "mtac"
     | JDG => "jdg"
     | TRIV => "triv"
     | MATCH_CLAUSE tau => "match-clause"
     | PARAM_EXP sigma => "param-exp{" ^ paramSortToString sigma ^ "}"
     | LVL => "lvl"
     | KIND => "kind"

  and paramSortToString = 
    fn DIM => "dim"
     | HYP => "hyp"
     | META_NAME => "meta-name"
     | OPID => "opid"
end

structure RedPrlParamData =
struct
  datatype 'a param_operator =
     DIM0
   | DIM1
end


structure RedPrlSort : ABT_SORT =
struct
  open RedPrlSortData

  type t = sort
  val eq : t * t -> bool = op=

  val toString = sortToString
end


structure RedPrlParamSort : ABT_SORT =
struct
  open RedPrlSortData RedPrlParamData

  type t = param_sort
  val eq : t * t -> bool = op=

  val toString = paramSortToString
end

structure RedPrlParameter : ABT_PARAMETER =
struct
  open RedPrlSortData RedPrlParamData
  type 'a t = 'a param_operator

  fun map f =
    fn DIM0 => DIM0
     | DIM1 => DIM1

  structure Sort = RedPrlParamSort

  val arity =
    fn DIM0 => (DIM0, DIM)
     | DIM1 => (DIM1, DIM)

  fun eq f =
    fn (DIM0, DIM0) => true
     | (DIM1, DIM1) => true
     | _ => false

  fun toString f =
    fn DIM0 => "0"
     | DIM1 => "1"

  fun join zer red =
    fn DIM0 => zer
     | DIM1 => zer
end

structure RedPrlParameterTerm = AbtParameterTerm (RedPrlParameter)


structure RedPrlArity = ListAbtArity (structure PS = RedPrlParamSort and S = RedPrlSort)


structure RedPrlKind =
struct
  (*
   * DISCRETE < KAN < HCOM < CUBICAL
   *                < COE  <
   *
   * and KAN = meet (HCOM, COE)
   *)

  (* Please keep the following invariants when adding new kinds:
   *
   * (1) All judgments should still be closed under any substitution! In
   *     particular, the property that a type A has kind K is closed under any
   *     substitution.
   * (2) If two types are related with respect to a stronger kind (like KAN),
   *     then they are related with respect to a weaker kind (like CUBICAL).
   *     A stronger kind might demand more things to be equal. For example,
   *     the equality between two types with respect to KAN means that they
   *     are equally Kan, while the equality with respect to CUBICAL only says
   *     they are equal cubical pretypes.
   * (3) The PER associated with A should *never* depend on its kind. Kinds
   *     should be properties of (the PER of) A.
   * (4) We say KAN = meet (HCOM, COE) because if two types are equally "HCOM"
   *     and equally "COE" then they are equally Kan. Always remember to check
   *     the binary cases.
   *)
  datatype kind = DISCRETE | KAN | HCOM | COE | CUBICAL

  val COM = KAN

  val toString =
    fn DISCRETE => "discrete"
     | KAN => "kan"
     | HCOM => "hcom"
     | COE => "coe"
     | CUBICAL => "cubical"

  local
    structure Internal :
    (* this could be the new meet semi-lattice *)
    sig
      type t = kind

      val top : t
      val <= : t * t -> bool
      val meet : t * t -> t

      (* residual (a, b)
       *
       * Let c be the greatest element such that `meet (b, c) <= a`.
       * The return value is SOME c if c is not top, or NONE otherwise.
       * *)
      val residual : t * t -> t option
    end
    =
    struct
      type t = kind
      val top = CUBICAL

      val meet =
        fn (DISCRETE, _) => DISCRETE
         | (_, DISCRETE) => DISCRETE
         | (KAN, _) => KAN
         | (_, KAN) => KAN
         | (HCOM, COE) => KAN
         | (COE, HCOM) => KAN
         | (HCOM, _) => HCOM
         | (_, HCOM) => HCOM
         | (COE, _) => COE
         | (_, COE) => COE
         | (CUBICAL, CUBICAL) => CUBICAL

      val residual =
        fn (_, DISCRETE) => NONE
         | (DISCRETE, _) => SOME DISCRETE
         | (_, KAN) => NONE
         | (KAN, HCOM) => SOME COE
         | (KAN, COE) => SOME HCOM
         | (KAN, _) => SOME KAN
         | (COE, HCOM) => SOME COE
         | (HCOM, COE) => SOME HCOM
         | (_, HCOM) => NONE
         | (HCOM, _) => SOME HCOM
         | (_, COE) => NONE
         | (COE, _) => SOME COE
         | (CUBICAL, CUBICAL) => NONE

      fun op <= (a, b) = residual (b, a) = NONE
    end
  in
    open Internal
  end
end

structure RedPrlOpData =
struct
  open RedPrlSortData
  structure P = RedPrlParameterTerm
  structure K = RedPrlKind
  type psort = RedPrlSortData.param_sort
  type kind = RedPrlKind.kind
  datatype 'a selector = IN_GOAL | IN_HYP of 'a

  datatype 'a dev_pattern = 
     PAT_VAR of 'a
   | PAT_TUPLE of (string * 'a dev_pattern) list

  (* We split our operator signature into a couple datatypes, because the implementation of
   * some of the 2nd-order signature obligations can be made trivial for "constant" operators,
   * which we call "monomorphic".
   *
   * Practically, the difference is:
   * MONO: the Standard ML built-in equality properly compares the operators.
   * POLY: we have to compare the operators manually. *)
  datatype mono_operator =
   (* the trivial realizer of sort TRIV for judgments lacking interesting
    * computational content. *)
     TV
   (* the trivial realizer of sort EXP for types lacking interesting
    * computational content. This is the "ax(iom)" in Nuprl. *)
   | AX
   (* strict bool *)
   | BOOL | TT | FF | IF
   (* week bool *)
   | WBOOL | WIF
   (* natural numbers *)
   | NAT | ZERO | SUCC | NAT_REC
   (* integers *)
   | INT | NEGSUCC | INT_REC
   (* empty type *)
   | VOID
   (* circle *)
   | S1 | BASE | S1_REC
   (* function: lambda and app *)
   | FUN | LAM | APP
   (* record and tuple *)
   | RECORD of string list | TUPLE of string list | PROJ of string | TUPLE_UPDATE of string
   (* path: path abstraction *)
   | PATH_TY | PATH_ABS
   (* equality *)
   | EQUALITY
   (* universe *)
   | UNIVERSE


   (* level expressions *)
   | LCONST of IntInf.int
   | LPLUS of IntInf.int
   | LMAX of int

   | KCONST of kind

   | JDG_EQ of bool
   | JDG_TRUE of bool 
   | JDG_EQ_TYPE of bool 
   | JDG_SUB_UNIVERSE of bool 
   | JDG_SYNTH of bool

   (* primitive tacticals and multitacticals *)
   | MTAC_SEQ of psort list | MTAC_ORELSE | MTAC_REC
   | MTAC_REPEAT | MTAC_AUTO | MTAC_PROGRESS
   | MTAC_ALL | MTAC_EACH of int | MTAC_FOCUS of int
   | MTAC_HOLE of string option
   | TAC_MTAC

   (* primitive rules *)
   | RULE_ID | RULE_AUTO_STEP | RULE_SYMMETRY | RULE_EXACT of sort | RULE_REDUCE_ALL
   | RULE_CUT
   | RULE_PRIM of string

   (* development calculus terms *)
   | DEV_FUN_INTRO of unit dev_pattern list
   | DEV_PATH_INTRO of int | DEV_RECORD_INTRO of string list
   | DEV_LET
   | DEV_MATCH of sort * int list
   | DEV_MATCH_CLAUSE of sort
   | DEV_QUERY_GOAL
   | DEV_PRINT of sort

   | JDG_TERM of sort
   | JDG_PARAM_SUBST of RedPrlParamSort.t list * sort

  type 'a equation = 'a P.term * 'a P.term
  type 'a dir = 'a P.term * 'a P.term

  datatype 'a poly_operator =
     FCOM of 'a dir * 'a equation list
   | LOOP of 'a P.term
   | PATH_APP of 'a P.term
   | BOX of 'a dir * 'a equation list
   | CAP of 'a dir * 'a equation list
   | V of 'a P.term
   | VIN of 'a P.term
   | VPROJ of 'a P.term
   | HCOM of 'a dir * 'a equation list
   | COE of 'a dir
   | COM of 'a dir * 'a equation list
   | CUST of 'a * ('a P.term * psort option) list * RedPrlArity.t option

   | PAT_META of 'a * sort * ('a P.term * psort) list * sort list
   | HYP_REF of 'a * sort
   | PARAM_REF of psort * 'a P.term

   | RULE_ELIM of 'a
   | RULE_REWRITE of 'a selector
   | RULE_REWRITE_HYP of 'a selector * 'a
   | RULE_REDUCE of 'a selector list
   | RULE_UNFOLD_ALL of 'a list
   | RULE_UNFOLD of 'a list * 'a selector list
   | DEV_BOOL_ELIM of 'a
   | DEV_S1_ELIM of 'a

   | DEV_APPLY_LEMMA of 'a * ('a P.term * psort option) list * RedPrlArity.t option * unit dev_pattern * int
   | DEV_APPLY_HYP of 'a * unit dev_pattern * int
   | DEV_USE_HYP of 'a * int
   | DEV_USE_LEMMA of 'a * ('a P.term * psort option) list * RedPrlArity.t option * int

  (* We split our operator signature into a couple datatypes, because the implementation of
   * some of the 2nd-order signature obligations can be made trivial for "constant" operators,
   * which we call "monomorphic". *)
  datatype 'a operator =
     MONO of mono_operator
   | POLY of 'a poly_operator
end

structure ArityNotation =
struct
  fun op* (a, b) = (a, b) (* symbols sorts, variable sorts *)
  fun op<> (a, b) = (a, b) (* valence *)
  fun op->> (a, b) = (a, b) (* arity *)
end

structure RedPrlOperator : ABT_OPERATOR =
struct
  structure Ar = RedPrlArity

  open RedPrlParamData RedPrlOpData
  open ArityNotation infix <> ->>

  type 'a t = 'a operator

  val rec devPatternSymValence = 
    fn PAT_VAR _ => [HYP]
     | PAT_TUPLE pats => List.concat (List.map (devPatternSymValence o #2) pats)

  val arityMono =
    fn TV => [] ->> TRIV
     | AX => [] ->> EXP

     | BOOL => [] ->> EXP
     | TT => [] ->> EXP
     | FF => [] ->> EXP
     | IF => [[] * [] <> EXP, [] * [] <> EXP, [] * [] <> EXP] ->> EXP

     | WBOOL => [] ->> EXP
     | WIF => [[] * [EXP] <> EXP, [] * [] <> EXP, [] * [] <> EXP, [] * [] <> EXP] ->> EXP

     | VOID => [] ->> EXP

     | NAT => [] ->> EXP
     | ZERO => [] ->> EXP
     | SUCC => [[] * [] <> EXP] ->> EXP
     | NAT_REC => [[] * [] <> EXP, [] * [] <> EXP, [] * [EXP, EXP] <> EXP] ->> EXP
     | INT => [] ->> EXP
     | NEGSUCC => [[] * [] <> EXP] ->> EXP
     | INT_REC => [[] * [] <> EXP, [] * [] <> EXP, [] * [EXP, EXP] <> EXP, [] * [] <> EXP, [] * [EXP, EXP] <> EXP] ->> EXP

     | S1 => [] ->> EXP
     | BASE => [] ->> EXP
     | S1_REC => [[] * [EXP] <> EXP, [] * [] <> EXP, [] * [] <> EXP, [DIM] * [] <> EXP] ->> EXP

     | FUN => [[] * [] <> EXP, [] * [EXP] <> EXP] ->> EXP
     | LAM => [[] * [EXP] <> EXP] ->> EXP
     | APP => [[] * [] <> EXP, [] * [] <> EXP] ->> EXP

     | RECORD lbls =>
       let
         val (_, valences) = List.foldr (fn (_, (taus, vls)) => (EXP :: taus, ([] * taus <> EXP) :: vls)) ([], []) lbls
       in 
         List.rev valences ->> EXP
       end
     | TUPLE lbls => (map (fn _ => ([] * [] <> EXP)) lbls) ->> EXP
     | PROJ lbl => [[] * [] <> EXP] ->> EXP
     | TUPLE_UPDATE lbl => [[] * [] <> EXP, [] * [] <> EXP] ->> EXP

     | PATH_TY => [[DIM] * [] <> EXP, [] * [] <> EXP, [] * [] <> EXP] ->> EXP
     | PATH_ABS => [[DIM] * [] <> EXP] ->> EXP

     | UNIVERSE => [[] * [] <> LVL, [] * [] <> KIND] ->> EXP
     | EQUALITY => [[] * [] <> EXP, [] * [] <> EXP, [] * [] <> EXP] ->> EXP

     | LCONST i => [] ->> LVL
     | LPLUS i => [[] * [] <> LVL] ->> LVL
     | LMAX n => List.tabulate (n, fn _ => [] * [] <> LVL) ->> LVL

     | KCONST _ => [] ->> KIND


     | JDG_EQ b => (if b then [[] * [] <> LVL] else []) @ [[] * [] <> KIND, [] * [] <> EXP, [] * [] <> EXP, [] * [] <> EXP] ->> JDG
     | JDG_TRUE b => (if b then [[] * [] <> LVL] else []) @ [[] * [] <> KIND, [] * [] <> EXP] ->> JDG
     | JDG_EQ_TYPE b => (if b then [[] * [] <> LVL] else []) @ [[] * [] <> KIND, [] * [] <> EXP, [] * [] <> EXP] ->> JDG
     | JDG_SUB_UNIVERSE b => (if b then [[] * [] <> LVL] else []) @ [[] * [] <> KIND, [] * [] <> EXP] ->> JDG
     | JDG_SYNTH b => (if b then [[] * [] <> LVL] else []) @ [[] * [] <> KIND, [] * [] <> EXP] ->> JDG

     | MTAC_SEQ psorts => [[] * [] <> MTAC, psorts * [] <> MTAC] ->> MTAC
     | MTAC_ORELSE => [[] * [] <> MTAC, [] * [] <> MTAC] ->> MTAC
     | MTAC_REC => [[] * [MTAC] <> MTAC] ->> MTAC
     | MTAC_REPEAT => [[] * [] <> MTAC] ->> MTAC
     | MTAC_AUTO => [] ->> MTAC
     | MTAC_PROGRESS => [[] * [] <> MTAC] ->> MTAC
     | MTAC_ALL => [[] * [] <> TAC] ->> MTAC
     | MTAC_EACH n =>
         let
           val tacs = List.tabulate (n, fn _ => [] * [] <> TAC)
         in
           tacs ->> MTAC
         end
     | MTAC_FOCUS _ => [[] * [] <> TAC] ->> MTAC
     | MTAC_HOLE _ => [] ->> MTAC
     | TAC_MTAC => [[] * [] <> MTAC] ->> TAC

     | RULE_ID => [] ->> TAC
     | RULE_AUTO_STEP => [] ->> TAC
     | RULE_SYMMETRY => [] ->> TAC
     | RULE_EXACT tau => [[] * [] <> tau] ->> TAC
     | RULE_REDUCE_ALL => [] ->> TAC
     | RULE_CUT => [[] * [] <> JDG] ->> TAC
     | RULE_PRIM _ => [] ->> TAC

     | DEV_FUN_INTRO pats => [List.concat (List.map devPatternSymValence pats) * [] <> TAC] ->> TAC
     | DEV_RECORD_INTRO lbls => List.map (fn _ => [] * [] <> TAC) lbls ->> TAC
     | DEV_PATH_INTRO n => [List.tabulate (n, fn _ => DIM) * [] <> TAC] ->> TAC
     | DEV_LET => [[] * [] <> JDG, [] * [] <> TAC, [HYP] * [] <> TAC] ->> TAC

     | DEV_MATCH (tau, ns) => ([] * [] <> tau) :: List.map (fn n => List.tabulate (n, fn _ => META_NAME) * [] <> MATCH_CLAUSE tau) ns ->> TAC
     | DEV_MATCH_CLAUSE tau => [[] * [] <> tau, [] * [] <> TAC] ->> MATCH_CLAUSE tau
     | DEV_QUERY_GOAL => [[] * [JDG] <> TAC] ->> TAC
     | DEV_PRINT tau => [[] * [] <> tau] ->> TAC

     | JDG_TERM _ => [] ->> JDG
     | JDG_PARAM_SUBST (sigmas, tau) => List.map (fn sigma => [] * [] <> PARAM_EXP sigma) sigmas @ [sigmas * [] <> tau] ->> JDG

  local
    fun arityFcom (_, eqs) =
      let
        val capArg = [] * [] <> EXP
        val tubeArgs = List.map (fn _ => [DIM] * [] <> EXP) eqs
      in
        capArg :: tubeArgs ->> EXP
      end
    fun arityBox (_, eqs) =
      let
        val capArg = [] * [] <> EXP
        val boundaryArgs = List.map (fn _ => [] * [] <> EXP) eqs
      in
        capArg :: boundaryArgs ->> EXP
      end
    fun arityCap (_, eqs) =
      let
        val tubeArgs = List.map (fn _ => [DIM] * [] <> EXP) eqs
        val coerceeArg = [] * [] <> EXP
      in
        (* note that the coercee goes first! *)
        coerceeArg :: tubeArgs ->> EXP
      end
    fun arityHcom (_, eqs) =
      let
        val typeArg = [] * [] <> EXP
        val capArg = [] * [] <> EXP
        val tubeArgs = List.map (fn _ => [DIM] * [] <> EXP) eqs
      in
        typeArg :: capArg :: tubeArgs ->> EXP
      end
    fun arityCom (_, eqs) =
      let
        val typeArg = [DIM] * [] <> EXP
        val capArg = [] * [] <> EXP
        val tubeArgs = List.map (fn _ => [DIM] * [] <> EXP) eqs
      in
        typeArg :: capArg :: tubeArgs ->> EXP
      end
  in
    val arityPoly =
      fn FCOM params => arityFcom params
       | LOOP _ => [] ->> EXP
       | PATH_APP _ => [[] * [] <> EXP] ->> EXP
       | BOX params => arityBox params
       | CAP params => arityCap params
       | V _ => [[] * [] <> EXP, [] * [] <> EXP, [] * [] <> EXP] ->> EXP
       | VIN _ => [[] * [] <> EXP, [] * [] <> EXP] ->> EXP
       | VPROJ _ => [[] * [] <> EXP, [] * [] <> EXP] ->> EXP

       | HCOM params => arityHcom params
       | COE _ => [[DIM] * [] <> EXP, [] * [] <> EXP] ->> EXP
       | COM params => arityCom params
       | CUST (_, _, ar) => Option.valOf ar

       | PAT_META (_, tau, _, taus) => List.map (fn tau => [] * [] <> tau) taus ->> tau
       | HYP_REF (_, tau) => [] ->> tau
       | PARAM_REF (sigma, _) => [] ->> PARAM_EXP sigma

       | RULE_ELIM _ => [] ->> TAC
       | RULE_REWRITE _ => [[] * [] <> EXP] ->> TAC
       | RULE_REWRITE_HYP _ => [] ->> TAC
       | RULE_REDUCE _ => [] ->> TAC
       | RULE_UNFOLD_ALL _ => [] ->> TAC
       | RULE_UNFOLD _ => [] ->> TAC
       | DEV_BOOL_ELIM _ => [[] * [] <> TAC, [] * [] <> TAC] ->> TAC
       | DEV_S1_ELIM _ => [[] * [] <> TAC, [DIM] * [] <> TAC] ->> TAC
       | DEV_APPLY_HYP (_, pat, n) => List.tabulate (n, fn _ => [] * [] <> TAC) @ [devPatternSymValence pat * [] <> TAC] ->> TAC
       | DEV_USE_HYP (_, n) => List.tabulate (n, fn _ => [] * [] <> TAC) ->> TAC
       | DEV_APPLY_LEMMA (_, _, ar, pat, n) => 
         let
           val (vls, tau) = Option.valOf ar
         in
           vls @ List.tabulate (n, fn _ => [] * [] <> TAC) @ [devPatternSymValence pat * [] <> TAC] ->> TAC
         end
       | DEV_USE_LEMMA (_, _, ar, n) => 
         let
           val (vls, tau) = Option.valOf ar
         in
           vls @ List.tabulate (n, fn _ => [] * [] <> TAC) ->> TAC
         end
  end

  val arity =
    fn MONO th => arityMono th
     | POLY th => arityPoly th

  local
    val dimSupport =
      fn P.VAR a => [(a, DIM)]
       | P.APP t => P.freeVars t

    val optSupport = OptionUtil.concat

    fun spanSupport (r, r') =
      dimSupport r @ dimSupport r'

    fun spansSupport ss =
      ListMonad.bind spanSupport ss

    fun comSupport (dir, eqs) =
      spanSupport dir @ spansSupport eqs

    fun paramsSupport ps =
      ListMonad.bind
        (fn (P.VAR a, SOME tau) => [(a, tau)]
          | (P.VAR _, NONE) => raise Fail "Encountered unannotated parameter in custom operator"
          | (P.APP t, _) => P.freeVars t)
        ps

    fun paramsSupport' ps =
      ListMonad.bind
        (fn (P.VAR a, tau) => [(a, tau)]
          | (P.APP t, _) => P.freeVars t)
        ps

    val selectorSupport =
      fn IN_GOAL => []
       | IN_HYP a => [(a, HYP)]

    fun selectorsSupport ps =
      ListMonad.bind selectorSupport ps

    fun opidsSupport os =
      List.map (fn name => (name, OPID)) os
  in
    val supportPoly =
      fn FCOM params => comSupport params
       | LOOP r => dimSupport r
       | PATH_APP r => dimSupport r
       | BOX params => comSupport params
       | CAP params => comSupport params
       | V r => dimSupport r
       | VIN r => dimSupport r
       | VPROJ r => dimSupport r
       | HCOM params => comSupport params
       | COE dir => spanSupport dir
       | COM params => comSupport params
       | CUST (opid, ps, _) => (opid, OPID) :: paramsSupport ps

       | PAT_META (x, _, ps, _) => (x, META_NAME) :: paramsSupport' ps
       | HYP_REF (a, _) => [(a, HYP)]
       | PARAM_REF (sigma, r) => paramsSupport [(r, SOME sigma)]

       | RULE_ELIM a => [(a, HYP)]
       | RULE_REWRITE sel => selectorSupport sel
       | RULE_REWRITE_HYP (sel, a) => selectorSupport sel @ [(a, HYP)]
       | RULE_REDUCE selectors => selectorsSupport selectors
       | RULE_UNFOLD_ALL names => opidsSupport names
       | RULE_UNFOLD (names, selectors) => opidsSupport names @ selectorsSupport selectors
       | DEV_BOOL_ELIM a => [(a, HYP)]
       | DEV_S1_ELIM a => [(a, HYP)]
       | DEV_APPLY_HYP (a, _, _) => [(a, HYP)]
       | DEV_USE_HYP (a, _) => [(a, HYP)]
       | DEV_APPLY_LEMMA (opid, ps, _, _, _) => (opid, OPID) :: paramsSupport ps
       | DEV_USE_LEMMA (opid, ps, _, _) => (opid, OPID) :: paramsSupport ps
  end

  val support =
    fn MONO _ => []
     | POLY th => supportPoly th

  local
    fun spanEq f ((r1, r'1), (r2, r'2)) =
      P.eq f (r1, r2) andalso P.eq f (r'1, r'2)

    fun spansEq f =
      ListPair.allEq (spanEq f)

    fun paramsEq f =
      ListPair.allEq (fn ((p, _), (q, _)) => P.eq f (p, q))

    val optEq = OptionUtil.eq

    fun selectorEq f =
      fn (IN_GOAL, IN_GOAL) => true
       | (IN_HYP a, IN_HYP b) => f (a, b)
       | _ => false

    fun selectorsEq f = ListPair.allEq (selectorEq f)

    fun opidsEq f = ListPair.allEq f
  in
    fun eqPoly f =
      fn (FCOM (dir1, eqs1), t) =>
         (case t of
             FCOM (dir2, eqs2) => spanEq f (dir1, dir2) andalso spansEq f (eqs1, eqs2)
           | _ => false)
       | (LOOP r, t) => (case t of LOOP r' => P.eq f (r, r') | _ => false)
       | (PATH_APP r, t) => (case t of PATH_APP r' => P.eq f (r, r') | _ => false)
       | (BOX (dir1, eqs1), t) =>
         (case t of
             BOX (dir2, eqs2) => spanEq f (dir1, dir2) andalso spansEq f (eqs1, eqs2)
           | _ => false)
       | (CAP (dir1, eqs1), t) =>
         (case t of
             CAP (dir2, eqs2) => spanEq f (dir1, dir2) andalso spansEq f (eqs1, eqs2)
           | _ => false)
       | (V r, t) => (case t of V r' => P.eq f (r, r') | _ => false)
       | (VIN r, t) => (case t of VIN r' => P.eq f (r, r') | _ => false)
       | (VPROJ r, t) => (case t of VPROJ r' => P.eq f (r, r') | _ => false)
       | (HCOM (dir1, eqs1), t) =>
         (case t of
             HCOM (dir2, eqs2) => spanEq f (dir1, dir2) andalso spansEq f (eqs1, eqs2)
           | _ => false)
       | (COE dir1, t) =>
         (case t of
             COE dir2 => spanEq f (dir1, dir2)
            | _ => false)
       | (COM (dir1, eqs1), t) =>
         (case t of
             COM (dir2, eqs2) => spanEq f (dir1, dir2) andalso spansEq f (eqs1, eqs2)
            | _ => false)
       | (CUST (opid1, ps1, _), t) =>
         (case t of
             CUST (opid2, ps2, _) => f (opid1, opid2) andalso paramsEq f (ps1, ps2)
           | _ => false)

       | (PAT_META (x1, tau1, ps1, taus1), t) => 
         (case t of 
             PAT_META (x2, tau2, ps2, taus2) => f (x1, x2) andalso tau1 = tau2 andalso paramsEq f (ps1, ps2) andalso taus1 = taus2
           | _ => false)
       | (HYP_REF (a, _), t) => (case t of HYP_REF (b, _) => f (a, b) | _ => false)
       | (PARAM_REF (sigma1, r1), t) => (case t of PARAM_REF (sigma2, r2) => sigma1 = sigma2 andalso P.eq f (r1, r2) | _ => false)

       | (RULE_ELIM a, t) => (case t of RULE_ELIM b => f (a, b) | _ => false)
       | (RULE_REWRITE s1, t) => (case t of RULE_REWRITE s2 => selectorEq f (s1, s2) | _ => false)
       | (RULE_REWRITE_HYP (s1, a), t) => (case t of RULE_REWRITE_HYP (s2, b) => selectorEq f (s1, s2) andalso f (a, b) | _ => false)
       | (RULE_REDUCE ss1, t) => (case t of RULE_REDUCE ss2 => selectorsEq f (ss1, ss2) | _ => false)
       | (RULE_UNFOLD_ALL os1, t) => (case t of RULE_UNFOLD_ALL os2 => opidsEq f (os1, os2) | _ => false)
       | (RULE_UNFOLD (os1, ss1), t) => (case t of RULE_UNFOLD (os2, ss2) => opidsEq f (os1, os2) andalso selectorsEq f (ss1, ss2) | _ => false)
       | (DEV_BOOL_ELIM a, t) => (case t of DEV_BOOL_ELIM b => f (a, b) | _ => false)
       | (DEV_S1_ELIM a, t) => (case t of DEV_S1_ELIM b => f (a, b) | _ => false)
       | (DEV_APPLY_HYP (a, pat, n), t) => (case t of DEV_APPLY_HYP (b, pat', n') => f (a, b) andalso pat = pat' andalso n = n' | _ => false)
       | (DEV_USE_HYP (a, n), t) => (case t of DEV_USE_HYP (b, n') => f (a, b) andalso n = n' | _ => false)
       | (DEV_APPLY_LEMMA (opid1, ps1, _, pat1, n1), t) =>
         (case t of
             DEV_APPLY_LEMMA (opid2, ps2, _, pat2, n2) => f (opid1, opid2) andalso paramsEq f (ps1, ps2) andalso pat1 = pat2 andalso n1 = n2
           | _ => false)
       | (DEV_USE_LEMMA (opid1, ps1, _, n1), t) =>
         (case t of
             DEV_USE_LEMMA (opid2, ps2, _, n2) => f (opid1, opid2) andalso paramsEq f (ps1, ps2) andalso n1 = n2
           | _ => false)

  end

  fun eq f =
    fn (MONO th1, MONO th2) => th1 = th2
     | (POLY th1, POLY th2) => eqPoly f (th1, th2)
     | _ => false

  val toStringMono =
    fn TV => "tv"
     | AX => "ax"

     | WBOOL => "wbool"
     | WIF => "wif"

     | BOOL => "bool"
     | TT => "tt"
     | FF => "ff"
     | IF => "if"

     | NAT => "nat"
     | NAT_REC => "nat-rec"
     | ZERO => "zero"
     | SUCC => "succ"
     | INT => "int"
     | NEGSUCC => "negsucc"
     | INT_REC => "int-rec"

     | VOID => "void"

     | S1 => "S1"
     | BASE => "base"
     | S1_REC => "S1-rec"

     | FUN => "fun"
     | LAM => "lam"
     | APP => "app"

     | RECORD lbls => "record{" ^ ListSpine.pretty (fn s => s) "," lbls ^ "}"
     | TUPLE lbls => "tuple{" ^ ListSpine.pretty (fn s => s) "," lbls ^ "}"
     | PROJ lbl => "proj{" ^ lbl ^ "}"
     | TUPLE_UPDATE lbl => "update{" ^ lbl ^ "}"

     | PATH_TY => "path"
     | PATH_ABS => "abs"

     | UNIVERSE => "U"
     | EQUALITY => "equality"

     | LCONST i => "{lconst " ^ IntInf.toString i  ^ "}"
     | LPLUS i => "{lsuc " ^ IntInf.toString i ^ "}"
     | LMAX n => "lmax"

     | KCONST k => RedPrlKind.toString k

     | MTAC_SEQ psorts => "seq{" ^ ListSpine.pretty RedPrlParamSort.toString "," psorts ^ "}"
     | MTAC_ORELSE => "orelse"
     | MTAC_REC => "rec"
     | MTAC_REPEAT => "repeat"
     | MTAC_AUTO => "auto"
     | MTAC_PROGRESS => "multi-progress"
     | MTAC_ALL => "all"
     | MTAC_EACH _ => "each"
     | MTAC_FOCUS i => "focus{" ^ Int.toString i ^ "}"
     | MTAC_HOLE (SOME x) => "?" ^ x
     | MTAC_HOLE NONE => "?"
     | TAC_MTAC => "mtac"

     | RULE_ID => "id"
     | RULE_AUTO_STEP => "auto-step"
     | RULE_SYMMETRY => "symmetry"
     | RULE_EXACT _ => "exact"
     | RULE_REDUCE_ALL => "reduce-all"
     | RULE_CUT => "cut"
     | RULE_PRIM name => "refine{" ^ name ^ "}"

     | DEV_PATH_INTRO n => "path-intro{" ^ Int.toString n ^ "}"
     | DEV_FUN_INTRO pats => "fun-intro"
     | DEV_RECORD_INTRO lbls => "record-intro{" ^ ListSpine.pretty (fn x => x) "," lbls ^ "}"
     | DEV_LET => "let"
     | DEV_MATCH _ => "dev-match"
     | DEV_MATCH_CLAUSE _ => "dev-match-clause"
     | DEV_QUERY_GOAL => "dev-query-goal"
     | DEV_PRINT _ => "dev-print"


     | JDG_EQ _ => "eq"
     | JDG_TRUE _ => "true"
     | JDG_EQ_TYPE _ => "eq-type"
     | JDG_SUB_UNIVERSE _ => "sub-universe"
     | JDG_SYNTH _ => "synth"

     | JDG_TERM tau => RedPrlSort.toString tau
     | JDG_PARAM_SUBST _ => "param-subst"

  local
    fun dirToString f (r, r') =
      P.toString f r ^ " ~> " ^ P.toString f r'

    fun equationToString f (r, r') =
      P.toString f r ^ "=" ^ P.toString f r'

    fun equationsToString f =
      ListSpine.pretty (equationToString f) ","

    fun paramsToString f =
      ListSpine.pretty (fn (p, _) => P.toString f p) ","

    fun comParamsToString f (dir, eqs) =
      dirToString f dir ^ ";" ^ equationsToString f eqs

    fun selectorToString f =
      fn IN_GOAL => "goal"
       | IN_HYP a => f a

    fun selectorsToString f =
      ListSpine.pretty (selectorToString f) ","

    fun opidsToString f =
      ListSpine.pretty f ","
  in
    fun toStringPoly f =
      fn FCOM params => "fcom{" ^ comParamsToString f params ^ "}"
       | LOOP r => "loop{" ^ P.toString f r ^ "}"
       | PATH_APP r => "pathapp{" ^ P.toString f r ^ "}"
       | BOX params => "box{" ^ comParamsToString f params ^ "}"
       | CAP params => "cap{" ^ comParamsToString f params ^ "}"
       | V r => "V{" ^ P.toString f r ^ "}"
       | VIN r => "Vin{" ^ P.toString f r ^ "}"
       | VPROJ r => "Vproj{" ^ P.toString f r ^ "}"
       | HCOM params => "hcom{" ^ comParamsToString f params ^ "}"
       | COE dir => "coe{" ^ dirToString f dir ^ "}"
       | COM params => "com{" ^ comParamsToString f params ^ "}"
       | CUST (opid, [], _) =>
           f opid
       | CUST (opid, ps, _) =>
           f opid ^ "{" ^ paramsToString f ps ^ "}"

       | PAT_META (x, _, ps, _) =>
           "?" ^ f x ^ "{" ^ paramsToString f ps ^ "}"
       | HYP_REF (a, _) => "hyp-ref{" ^ f a ^ "}"
       | PARAM_REF (_, r) => "param-ref{" ^ P.toString f r ^ "}"

       | RULE_ELIM a => "elim{" ^ f a ^ "}"
       | RULE_REWRITE s => "rewrite{" ^ selectorToString f s ^ "}"
       | RULE_REWRITE_HYP (s, a) => "rewrite-hyp{" ^ selectorToString f s ^ "," ^ f a ^ "}"
       | RULE_REDUCE ss => "reduce{" ^ selectorsToString f ss ^ "}"
       | RULE_UNFOLD_ALL os => "unfold-all{" ^ opidsToString f os ^ "}"
       | RULE_UNFOLD (os, ss) => "unfold{" ^ opidsToString f os ^ "," ^ selectorsToString f ss ^ "}"
       | DEV_BOOL_ELIM a => "bool-elim{" ^ f a ^ "}"
       | DEV_S1_ELIM a => "s1-elim{" ^ f a ^ "}"
       | DEV_APPLY_HYP (a, _, _) => "apply-hyp{" ^ f a ^ "}"
       | DEV_USE_HYP (a, _) => "use-hyp{" ^ f a ^ "}"
       | DEV_APPLY_LEMMA (opid, ps, _, _, _) => "apply-lemma{" ^ f opid ^ "}{" ^ paramsToString f ps ^ "}"
       | DEV_USE_LEMMA (opid, ps, _, _) => "use-lemma{" ^ f opid ^ "}{" ^ paramsToString f ps ^ "}"
  end

  fun toString f =
    fn MONO th => toStringMono th
     | POLY th => toStringPoly f th

  local
    fun passSort sigma f =
      fn u => f (u, sigma)

    val mapOpt = Option.map

    fun mapSpan f (r, r') = (P.bind (passSort DIM f) r, P.bind (passSort DIM f) r')
    fun mapSpans f = List.map (mapSpan f)
    fun mapParams (f : 'a * psort -> 'b P.term) =
      List.map
        (fn (p, SOME tau) =>
           let
             val q = P.bind (passSort tau f) p
             val _ = P.check tau q
           in
             (q, SOME tau)
           end
          | _ => raise Fail "operator.sml, uh-oh")

    fun mapParams' (f : 'a * psort -> 'b P.term) =
      List.map
        (fn (p, tau) =>
           let
             val q = P.bind (passSort tau f) p
             val _ = P.check tau q
           in
             (q, tau)
           end)

    fun mapSym f a =
      case f a of
         P.VAR a' => a'
       | P.APP _ => raise Fail "Expected symbol, but got application"

    fun mapSelector f =
      fn IN_GOAL => IN_GOAL
       | IN_HYP a => IN_HYP (f a)
  in
    fun mapPolyWithSort f =
      fn FCOM (dir, eqs) => FCOM (mapSpan f dir, mapSpans f eqs)
       | LOOP r => LOOP (P.bind (passSort DIM f) r)
       | PATH_APP r => PATH_APP (P.bind (passSort DIM f) r)
       | BOX (dir, eqs) => BOX (mapSpan f dir, mapSpans f eqs)
       | CAP (dir, eqs) => CAP (mapSpan f dir, mapSpans f eqs)
       | V r => V (P.bind (passSort DIM f) r)
       | VIN r => VIN (P.bind (passSort DIM f) r)
       | VPROJ r => VPROJ (P.bind (passSort DIM f) r)
       | HCOM (dir, eqs) => HCOM (mapSpan f dir, mapSpans f eqs)
       | COE dir => COE (mapSpan f dir)
       | COM (dir, eqs) => COM (mapSpan f dir, mapSpans f eqs)
       | CUST (opid, ps, ar) => CUST (mapSym (passSort OPID f) opid, mapParams f ps, ar)

       | PAT_META (x, tau, ps, taus) => PAT_META (mapSym (passSort META_NAME f) x, tau, mapParams' f ps, taus)
       | HYP_REF (a, tau) => HYP_REF (mapSym (passSort HYP f) a, tau)
       | PARAM_REF (sigma, r) => PARAM_REF (sigma, P.bind (passSort sigma f) r)

       | RULE_ELIM a => RULE_ELIM (mapSym (passSort HYP f) a)
       | RULE_REWRITE s => RULE_REWRITE (mapSelector (mapSym (passSort HYP f)) s)
       | RULE_REWRITE_HYP (s, a) => RULE_REWRITE_HYP (mapSelector (mapSym (passSort HYP f)) s, mapSym (passSort HYP f) a)
       | RULE_REDUCE ss => RULE_REDUCE (List.map (mapSelector (mapSym (passSort HYP f))) ss)
       | RULE_UNFOLD_ALL ns => RULE_UNFOLD_ALL (List.map (mapSym (passSort OPID f)) ns)
       | RULE_UNFOLD (ns, ss) => RULE_UNFOLD (List.map (mapSym (passSort OPID f)) ns, List.map (mapSelector (mapSym (passSort HYP f))) ss)
       | DEV_BOOL_ELIM a => DEV_BOOL_ELIM (mapSym (passSort HYP f) a)
       | DEV_S1_ELIM a => DEV_S1_ELIM (mapSym (passSort HYP f) a)
       | DEV_APPLY_LEMMA (opid, ps, ar, pat, n) => DEV_APPLY_LEMMA (mapSym (passSort OPID f) opid, mapParams f ps, ar, pat, n)
       | DEV_APPLY_HYP (a, pat, spine) => DEV_APPLY_HYP (mapSym (passSort HYP f) a, pat, spine)
       | DEV_USE_HYP (a, n) => DEV_USE_HYP (mapSym (passSort HYP f) a, n)
       | DEV_USE_LEMMA (opid, ps, ar, n) => DEV_USE_LEMMA (mapSym (passSort OPID f) opid, mapParams f ps, ar, n)
  end

  fun mapWithSort f =
    fn MONO th => MONO th
     | POLY th => POLY (mapPolyWithSort f th)

  fun map f = 
    mapWithSort (fn (u, _) => f u)
end
