functor RefinerIndSpec (Sig : MINI_SIGNATURE) =
struct
  structure Kit = RefinerKit (Sig)
  structure ComRefinerKit = RefinerCompositionKit (Sig)
  open RedPrlAbt Kit ComRefinerKit
  type hyp = Sym.t
  infixr @@
  infix 1 || #>
  infix 2 >> >: >:? >:+ $$ $# // \ @>

  structure InductiveSpec =
  struct

    val IND_SPECTYPE_SELF = Syn.into Syn.IND_SPECTYPE_SELF

    structure ConstrDict = StringListDict
    structure SpecCtx = Var.Ctx
    structure DimSet = ListSet (structure Elem = Sym.Ord)
    type constrs = abt ConstrDict.dict
    type specctx = abt SpecCtx.dict
    type dimset = DimSet.set

    val trace = ["InductiveSpec"]

    (* TODO tail recursion *)

    fun EqSpecType H ((ty0, ty1), level) =
      case (Syn.out ty0, Syn.out ty1) of
         (Syn.IND_SPECTYPE_SELF, Syn.IND_SPECTYPE_SELF) => []
       | (Syn.IND_SPECTYPE_FUN (a0, x, b0x), Syn.IND_SPECTYPE_FUN (a1, y, b1y)) =>
           let
             val z = Sym.new ()
             val b0z = VarKit.rename (z, x) b0x
             val b1z = VarKit.rename (z, y) b1y
             (* favonia: more research needed for other kinds *)
             val goalA = makeEq trace H ((a0, a1), Syn.intoU (level, K.COE))
           in
             goalA :: EqSpecType (H @> (z, AJ.TRUE a0)) ((b0z, b1z), level)
           end

    fun SpecType H (ty, level) = EqSpecType H ((ty, ty), level)

    (* The following checker type-checks more expressions than the rules
     * on paper because `($ (lam [_] foo) junk)` and `(fcom 0~>0 m [... junk])` are allowed.
     * This is to solve the difficulty to generate a valid type for `junk`
     * in the first case. One easy solution is to beta-reduce everything first.
     *
     * This extension is implemented as `untypedReduce`.
     *
     * -favonia
     *)

    fun untypedReduce tm : abt =
      case Syn.out tm of
         Syn.IND_SPEC_INTRO params => tm
       | Syn.IND_SPEC_FCOM {dir, cap, ...} =>
           if Abt.eq dir then cap else tm
       | Syn.IND_SPEC_LAM (x, ax) =>
           Syn.into (Syn.IND_SPEC_LAM (x, untypedReduce ax))
       | Syn.IND_SPEC_APP (a, b) =>
           case Syn.out (untypedReduce a) of
              Syn.IND_SPEC_LAM (x, ax) => untypedReduce (Abt.substVar (b, x) ax)
            | a => Syn.into (Syn.IND_SPEC_APP (Syn.into a, b))

    fun SynthReduced H (constrs, specctx) (tm0, tm1) =
      case (Syn.out tm0, Syn.out tm1) of
         (Syn.VAR (x, _), Syn.VAR (y, _)) =>
           let
             val _ = Assert.varEq (x, y)
             val ty = SpecCtx.lookup specctx x
           in
             (ty, [])
           end
       | (Syn.IND_SPEC_APP (m0, n0), Syn.IND_SPEC_APP (m1, n1)) =>
           let
             val (ty, goalsM) = SynthReduced H (constrs, specctx) (m0, m1)
             val Syn.IND_SPECTYPE_FUN (a0, x, b0x) = Syn.out ty
             val goalN = makeEq trace H ((n0, n1), a0)
           in
             (Abt.substVar (n0, x) b0x, goalsM @ [goalN])
           end
       | (tm0', tm1') =>
           (case (simplifyConstr H (constrs, specctx) tm0', simplifyConstr H (constrs, specctx) tm1') of
              (SOME (tm0, goals0), SOME (tm1, goals1)) =>
                (IND_SPECTYPE_SELF, goals0 @ goals1 @ EqSpec H (constrs, specctx) ((tm0, tm1), IND_SPECTYPE_SELF))
            | (SOME (tm0, goals0), NONE) =>
                (IND_SPECTYPE_SELF, goals0 @ EqSpec H (constrs, specctx) ((tm0, tm1), IND_SPECTYPE_SELF))
            | (NONE, SOME (tm1, goals1)) =>
                (IND_SPECTYPE_SELF, goals1 @ EqSpec H (constrs, specctx) ((tm0, tm1), IND_SPECTYPE_SELF))
            | (NONE, NONE) =>
                (case (tm0', tm1') of
                   (Syn.IND_SPEC_FCOM params0, Syn.IND_SPEC_FCOM params1) =>
                     (IND_SPECTYPE_SELF, EqSpecFCom H (constrs, specctx) (params0, params1))
                 | (Syn.IND_SPEC_INTRO params0, Syn.IND_SPEC_INTRO params1) =>
                     (IND_SPECTYPE_SELF, EqSpecIntro H (constrs, specctx) (params0, params1))))

    and EqSpec H (constrs, specctx) (((tm0, tm1), ty) : (abt * abt) * abt)=
      case Syn.out ty of
         Syn.IND_SPECTYPE_FUN (a, z, bz) =>
           let
             val w = Sym.new ()
             val bw = VarKit.rename (w, z) bz
           in
             EqSpec (H @> (w, AJ.TRUE a)) (constrs, specctx)
               ((Syn.into (Syn.IND_SPEC_APP (tm0, VarKit.toExp w)),
                 Syn.into (Syn.IND_SPEC_APP (tm1, VarKit.toExp w))), bw)
           end
       | Syn.IND_SPECTYPE_SELF =>
           let
             val (ty, goals) = SynthReduced H (constrs, specctx)
               (untypedReduce tm0, untypedReduce tm1)
           in
             case Syn.out ty of Syn.IND_SPECTYPE_SELF => goals
           end

    and EqSpecIfDifferent H (constrs, specctx) ((tm0, tm1), ty) =
      if Abt.eq (tm0, tm1) then [] else EqSpec H (constrs, specctx) ((tm0, tm1), ty)

    and restrictedEqSpec eqs H (constrs, specctx) ((tm0, tm1), ty) =
      case Restriction.restrict eqs of
         SOME f => EqSpec
           (Hyps.map (AJ.map f) H)
           (ConstrDict.map f constrs, SpecCtx.map f specctx)
           ((f tm0, f tm1), f ty)
       | NONE => []

    and restrictedEqSpecIfDifferent eqs H (constrs, specctx) ((tm0, tm1), ty) =
      case Restriction.restrict eqs of
         SOME f => EqSpecIfDifferent
           (Hyps.map (AJ.map f) H)
           (ConstrDict.map f constrs, SpecCtx.map f specctx)
           ((f tm0, f tm1), f ty)
       | NONE => []

    and EqSpecInterTube H (constrs, specctx) w (tubes0, tubes1) =
      let
        val tubes0 = ComKit.alphaRenameTubes w tubes0
        val tubes1 = ComKit.alphaRenameTubes w tubes1

        val goalsOnDiag = List.concat @@
          ListPair.mapEq
            (fn ((eq, t0), (_, t1)) =>
              restrictedEqSpec [eq]
                (H @> (w, AJ.TERM O.DIM))
                (constrs, specctx)
                ((t0, t1), IND_SPECTYPE_SELF))
            (tubes0, tubes1)

        val goalsNotOnDiag = List.concat @@
          ComKit.enumInterExceptDiag
            (fn ((eq0, t0), (eq1, t1)) =>
              restrictedEqSpecIfDifferent [eq0, eq1]
                (H @> (w, AJ.TERM O.DIM))
                (constrs, specctx)
                ((t0, t1), IND_SPECTYPE_SELF))
            (tubes0, tubes1)
      in
        goalsOnDiag @ goalsNotOnDiag
      end

    and EqSpecCapTubeIfDifferent H (constrs, specctx) (cap, (r, tubes)) = List.concat @@
      List.map
        (fn (eq, (u, tube)) =>
          restrictedEqSpecIfDifferent [eq] H (constrs, specctx)
            ((cap, substVar (r, u) tube), IND_SPECTYPE_SELF))
        tubes

    and EqSpecFCom H (constrs, specctx)
      ({dir=dir0, cap=cap0, tubes=tubes0},
       {dir=dir1, cap=cap1, tubes=tubes1}) =
      let
        val _ = Assert.dirEq "EqSpecFCom direction" (dir0, dir1)

        val eqs0 = List.map #1 tubes0
        val eqs1 = List.map #1 tubes1
        val _ = Assert.equationsEq "EqSpecFCom equations" (eqs0, eqs1)
        val _ = Assert.tautologicalEquations "EqSpecFCom tautology checking" eqs0

        val goalsCap = EqSpec H (constrs, specctx) ((cap0, cap1), IND_SPECTYPE_SELF)
        val w = Sym.new ()
        val goalsInterTube = EqSpecInterTube H (constrs, specctx) w (tubes0, tubes1)
        val goalsCapTube = EqSpecCapTubeIfDifferent H (constrs, specctx) (cap0, (#1 dir0, tubes0))
      in
        goalsCap @ goalsInterTube @ goalsCapTube
      end

    and simplifyFComTube H (constrs, specctx) {dir, cap, tubes} =
      Option.map
        (fn (_, (u, tube)) =>
          let
            val w = Sym.new ()
            val goalsInterTube = EqSpecInterTube H (constrs, specctx) w (tubes, tubes)
            val goalsCapTube = EqSpecCapTubeIfDifferent H (constrs, specctx) (cap, (#1 dir, tubes))
          in
            (substVar (#2 dir, u) tube, goalsInterTube @ goalsCapTube)
          end)
      (List.find (fn (eq, _) => Abt.eq eq) tubes)

    and EqSpecIntro H (constrs, specctx) ((label0, args0), (label1, args1)) =
      let
        val true = label0 = label1
        fun goals' (([], []), Syn.IND_CONSTR_DISCRETE _) = []
          | goals' (([], []), Syn.IND_CONSTR_KAN _) = []
          | goals' ((arg0::args0, arg1::args1), Syn.IND_CONSTR_FUN (a,x,bx)) =
              let
                val goal = makeEq trace H ((arg0, arg1), a)
              in
                goal :: goals ((args0, args1), Abt.substVar (arg0, x) bx)
              end
          | goals' ((arg0::args0, arg1::args1), Syn.IND_CONSTR_SPEC_FUN (a,x,bx)) =
              let
                val goalsSpec = EqSpec H (constrs, specctx) ((arg0, arg1), a)
              in
                goalsSpec @ goals ((args0, args1), Abt.substVar (arg0, x) bx)
              end
          | goals' ((arg0::args0, arg1::args1), Syn.IND_CONSTR_LINE (x,bx)) =
              let
                (* XXX no sort-checking *)
                val _ = Assert.alphaEq (arg0, arg1)
              in
                goals ((args0, args1), Abt.substVar (arg0, x) bx)
              end
        and goals (argsPair, spec) = goals' (argsPair, Syn.out spec)
      in
        goals ((args0, args1), ConstrDict.lookup constrs label0)
      end

    and simplifyIntro H (constrs, specctx) (label, args) =
      let
        fun trySimplify' ([], Syn.IND_CONSTR_DISCRETE boundaries) =
              Option.map (fn (_, boundary) => (boundary, []))
                (List.find (fn (eq, _) => Abt.eq eq) boundaries)
          | trySimplify' ([], Syn.IND_CONSTR_KAN boundaries) =
              Option.map (fn (_, boundary) => (boundary, []))
                (List.find (fn (eq, _) => Abt.eq eq) boundaries)
          | trySimplify' (arg::args, Syn.IND_CONSTR_FUN (a,x,bx)) =
              Option.map
                (fn (boundary, goals) =>
                  let
                    val goal = makeMem trace H (arg, a)
                  in
                    (boundary, goal :: goals)
                  end)
                (trySimplify (args, Abt.substVar (arg, x) bx))
          | trySimplify' (arg::args, Syn.IND_CONSTR_SPEC_FUN (a,x,bx)) =
              Option.map
                (fn (boundary, goals) =>
                  let
                    val goalsSpec = EqSpec H (constrs, specctx) ((arg, arg), a)
                  in
                    (boundary, goalsSpec @ goals)
                  end)
                (trySimplify (args, Abt.substVar (arg, x) bx))
          | trySimplify' (arg::args, Syn.IND_CONSTR_LINE (x,bx)) =
              (* XXX no sort-checking *)
              trySimplify (args, Abt.substVar (arg, x) bx)
        and trySimplify (args, spec) = trySimplify' (args, Syn.out spec)
      in
        trySimplify (args, ConstrDict.lookup constrs label)
      end

    and simplifyConstr H (constrs, specctx) =
      fn Syn.IND_SPEC_INTRO args => simplifyIntro H (constrs, specctx) args
       | Syn.IND_SPEC_FCOM args => simplifyFComTube H (constrs, specctx) args

    fun EqSpecInterBoundary H (constrs, specctx) boundaries =
      let
        val goalsOnDiag = List.concat @@
          List.map
            (fn (eq, b) =>
              restrictedEqSpec [eq] H (constrs, specctx)
                ((b, b), IND_SPECTYPE_SELF))
            boundaries

        val goalsNotOnDiag = List.concat @@
          ComKit.enumInterExceptDiag
            (fn ((eq0, b0), (eq1, b1)) =>
              restrictedEqSpecIfDifferent [eq0, eq1] H (constrs, specctx)
                ((b0, b1), IND_SPECTYPE_SELF))
            (boundaries, boundaries)
      in
        goalsOnDiag @ goalsNotOnDiag
      end

    (* Is it okay to move dimensions upfront? It is banned in Part IV,
     * and the parser disallows it, but the checker here allows this.
     *)
    fun checkConstr' (H, dimset) (constrs, specctx) constr level =
      case Syn.out constr of
         Syn.IND_CONSTR_DISCRETE [] => [] (* XXX more refined criterion *)
       | Syn.IND_CONSTR_KAN boundaries =>
           let
             val eqs = List.map #1 boundaries
             fun inSet dim =
               case Syn.out dim of
                  Syn.DIM0 => true
                | Syn.DIM1 => true
                | Syn.VAR (v, _) => DimSet.member dimset v
             val true = List.all (fn (r0, r1) => inSet r0 andalso inSet r1) eqs
             val _ = Assert.tautologicalEquations "checkConstr' tautology checking" eqs
           in
             EqSpecInterBoundary H (constrs, specctx) boundaries
           end
       | Syn.IND_CONSTR_FUN (a,x,bx) =>
           let
             val w = Sym.new () (* is it possible to save this? *)
             val goal = makeMem trace H (a, Syn.intoU (level, K.COE))
             val rest = checkConstr' (H @> (w, AJ.TRUE a), dimset) (constrs, specctx) (VarKit.rename (w, x) bx) level
           in
             goal :: rest
           end
       | Syn.IND_CONSTR_SPEC_FUN (a,x,bx) =>
           let
             val w = Sym.new () (* is it possible to save this? *)
             val goals = SpecType H (a, level)
             val rest = checkConstr' (H, dimset) (constrs, SpecCtx.insert specctx w a) (VarKit.rename (w, x) bx) level
           in
             goals @ rest
           end
       | Syn.IND_CONSTR_LINE (x,bx) =>
           let
             val w = Sym.new () (* is it possible to save this? *)
           in
             checkConstr' (H @> (w, AJ.TERM O.DIM), DimSet.insert dimset w) (constrs, specctx) (VarKit.rename (w, x) bx) level
           end
    fun checkConstr H constrs constr level =
      checkConstr' (H, DimSet.empty) (constrs, SpecCtx.empty) constr level

    fun checkConstrs H constrs level = List.concat @@ List.rev @@ #2 @@
      List.foldl
        (fn ((label, constr), (prefix, accumulatedGoals)) =>
          let
            val newgoals = checkConstr H prefix constr level
            val (prefix, present) = ConstrDict.insert' prefix label constr
            val _ = if present then E.raiseError (E.GENERIC [Fpp.text "Duplicate constructors"]) else ()
          in
            (prefix, newgoals :: accumulatedGoals)
          end)
        (ConstrDict.empty, [])
        constrs

    fun checkFam' H desc =
      case Syn.out desc of
         Syn.IND_FAM_BASE (level, constrs) => checkConstrs H constrs level
       | Syn.IND_FAM_FUN (a,x,bx) =>
           let
             val w = Sym.new () (* can we avoid this? *)
             val goal = makeType trace H (a, K.top)
           in
             goal :: checkFam' (H @> (w, AJ.TRUE a)) (VarKit.rename (w, x) bx)
           end
       | Syn.IND_FAM_LINE (x,bx) =>
           let
             val w = Sym.new () (* can we avoid this? *)
           in
             checkFam' (H @> (w, AJ.TERM O.DIM)) (VarKit.rename (w, x) bx)
           end
    val checkFam = checkFam' Hyps.empty
  end
end