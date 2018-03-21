functor MlElaborate (R : RESOLVER where type id = MlId.t where type mltype = MlType.vty) : ML_ELABORATE =
struct
  structure Ty = MlType
  structure ESyn = MlExtSyntax
  structure ISyn = MlIntSyntax

  type env = R.env
  type ivalue = ISyn.value
  type icmd = ISyn.cmd
  type evalue = ESyn.value
  type ecmd = ESyn.cmd
  type vty = Ty.vty
  type cty = Ty.cty

  structure Ast = RedPrlAst and AJ = AtomicJudgment
  type ast = Ast.ast
  type abt = Tm.abt
  type sort = Tm.sort

  exception todo fun ?e = raise e
  fun @@ (f, x) = f x
  infixr @@


  structure O = RedPrlOperator and S = RedPrlSort and Err = RedPrlError
  type arity = O.Ar.t


  fun lookupArity (env : env) (pos : Pos.t option) (opid : MlId.t) : arity =
    case R.lookupId env pos opid of
        Ty.ABS (vls, Ty.TERM tau) => (vls, tau)
      | Ty.ABS (vls, Ty.THM tau) => (vls, tau)
      | _ => Err.raiseAnnotatedError' (pos, Err.GENERIC [Fpp.text "Could not infer arity for opid", Fpp.text (MlId.toString opid)])

  fun checkAbt pos (view, tau) : abt =
    Tm.setAnnotation pos @@ Tm.check (view, tau)
    handle exn =>
      Err.raiseAnnotatedError' (pos, Err.GENERIC [Fpp.text "Error resolving abt:", Fpp.text (exnMessage exn)])

  fun guessSort (env : env) (ast : ast) : sort =
    let
      val pos = Ast.getAnnotation ast
    in
      case Ast.out ast of
          Ast.` x =>
          #2 @@ R.lookupVar env pos x

        | Ast.$# (X, _) =>
          #2 o #2 @@ R.lookupMeta env pos X

        | Ast.$ (O.CUST (opid, _), _) =>
          #2 @@ lookupArity env pos opid

        | Ast.$ (theta, _) =>
          (#2 @@ O.arity theta
          handle _ => Err.raiseError @@ Err.GENERIC [Fpp.text "Error guessing sort"])
    end

  fun elabAtomicJdg (env : env) (ast : ast) : AJ.jdg =
    let
      val abt = elabAst env (ast, S.JDG)
    in
      AJ.out abt
      handle _ =>
        Err.raiseError @@ Err.GENERIC [Fpp.text "Expected atomic judgment but got", TermPrinter.ppTerm abt]
    end

  and elabAst (env : env) (ast : ast, tau : sort) : abt =
    let
      val pos = Ast.getAnnotation ast
    in
      case Ast.out ast of
          Ast.` x =>
          checkAbt pos (Tm.` o #1 @@ R.lookupVar env pos x, tau)

        | Ast.$# (X, asts : ast list) =>
          let
            val (X', (taus, _)) = R.lookupMeta env pos X
            val _ =
              if List.length asts = List.length taus then () else
                Err.raiseAnnotatedError' (pos, Err.GENERIC [Fpp.text "Incorrect valence for metavariable", Fpp.text X])
            val abts = ListPair.map (elabAst env) (asts, taus)
          in
            checkAbt pos (Tm.$# (X', abts), tau)
          end

        | Ast.$ (theta, bs) =>
          let
            val theta' = elabOpr env pos theta bs
            val ar as (vls, tau) = O.arity theta'
            val _ =
              if List.length bs = List.length vls then () else
                Err.raiseAnnotatedError' (pos, Err.INCORRECT_ARITY theta')
            val bs' = ListPair.map (elabBnd env) (vls, bs)
          in
            checkAbt pos (Tm.$ (theta', bs'), tau)
          end
    end

  and elabBnd (env : env) ((taus, tau), Ast.\ (xs, ast)) : abt Tm.bview =
    let
      val (xs', env') = R.extendVars env (xs, taus)
    in
      Tm.\ (List.map #1 xs', elabAst env' (ast, tau))
    end

  and elabOpr (env : env) (pos : Pos.t option) (theta : O.operator) (bs : ast Ast.abs list) : O.operator =
    (case theta of
        O.CUST (opid, NONE) =>
        O.CUST (opid, SOME @@ lookupArity env pos opid)

      | O.MK_ANY NONE =>
        let
          val [Ast.\ (_, ast)] = bs
        in
          O.MK_ANY o SOME @@ guessSort env ast
        end

      | O.DEV_CLAIM NONE =>
        let
          val [Ast.\ (_, jdg), _, _] = bs
        in
          O.DEV_CLAIM o SOME o AJ.synthesis @@ elabAtomicJdg env jdg
        end

      | th => th)
      handle _ =>
        Err.raiseAnnotatedError' (pos, Err.GENERIC @@ [Fpp.text "Error resolving operator"])





  type 'a elab = env -> 'a

  structure ElabRx = 
  struct
    structure Rx = RedExpr

    datatype head = 
       VAR of Tm.variable * Tm.sort
     | META of Tm.metavariable * Tm.valence
     | CUST of MlId.t * arity
    
    val <+> : 'a elab * 'a elab -> 'a elab =
      fn (el1, el2) => 
        fn env =>
          el1 env
          handle _ => el2 env

    infixr <+>

    val ret : 'a -> 'a elab = 
      fn a => fn _ => a

    val <$> : ('a -> 'b) * 'a elab -> 'b elab = 
      fn (f, x) => fn env => 
        f (x env)

    val >>= : 'a elab * ('a -> 'b elab) -> 'b elab = 
      fn (m, k) => fn env =>
        k (m env) env

    fun throw exn = 
      fn _ => 
        raise exn

    infix <$> >>=

    open Tm infix 4 $$ \ $ $#
    structure O = RedPrlOperator

    fun traverse (f : 'a -> 'b elab) (xs : 'a list) : 'b list elab = 
      case xs of 
         [] => ret []
       | x::xs =>
         f x >>= (fn y => traverse f xs >>= (fn ys => ret @@ y :: ys))

    fun bindVar (x, tau) (k : Tm.variable -> 'a elab) : 'a elab =
      fn env => 
        let
          val ([(x', _)], env') = R.extendVars env ([x], [tau])
        in
          k x' env'
        end

    fun nodeAsAtom node : string Rx.info elab = fn _ =>
      let
        val Rx.NODE {con = Rx.ATOM str, pos} = node
      in
        {con = str, pos = pos}
      end

    fun elabVar node : head elab = fn env =>
      let
        val {pos, con = atom} = nodeAsAtom node env
        val (var, tau) = R.lookupVar env pos atom
      in
        VAR (var, tau)
      end

    fun elabMeta node : head elab = fn env =>
      let
        val {pos, con = atom} = nodeAsAtom node env      
        val (mvar, vl) = R.lookupMeta env pos atom
      in
        META (mvar, vl)
      end

    fun elabCust node : head elab = fn env => 
      let
        val {pos, con = atom} = nodeAsAtom node env
        val opid = MlId.const atom
      in
        CUST (opid, lookupArity env pos opid)
      end

    fun elabHead node = 
      elabVar node
        <+> elabMeta node
        <+> elabCust node

    val headAsAbt : head -> abt = 
      fn VAR (x, tau) =>
         Tm.check (` x, tau)

       | META (x, (_, tau)) =>
         Tm.check (x $# [], tau)

       | CUST (th, ar) =>
         Tm.$$ (O.CUST (th, SOME ar), [])


    fun elabAbt (node as Rx.NODE {pos, con}) : abt elab = 
      case con of 
         Rx.ATOM atom =>
         headAsAbt <$> elabHead node

       | Rx.LIST (rxhead :: rxtail) =>
         elabList rxhead rxtail

       | _ =>
        Err.raiseAnnotatedError'
          (pos,
           Err.GENERIC @@ [Fpp.text "Error reading rexpr"])

    and elabProductType _ = ?todo
    and elabRecordType _ = ?todo

    and elabTuple rxs =
      traverse elabLabelCell rxs >>= (fn cells =>
        let
          val (lbls, abts) = ListPair.unzip cells
          val bs = List.map (fn abt => Tm.\ ([], abt)) abts
        in
          ret @@ Tm.$$ (O.TUPLE lbls, bs)
        end)

    and elabLabelCell node : (string * abt) elab = fn env =>
      let
        val Rx.NODE {con = Rx.LABEL_CELL (lbl, node'), ...} = node
      in
        (lbl, elabAbt node' env)
      end

    and elabOperator pos atom = fn env =>
      case atom of 
         _ =>
         let 
           val opid = MlId.const atom
           val ar = lookupArity env pos opid
         in
           O.CUST (opid, SOME ar)
         end


    and elabOpApp theta rxtail =
      let
        val ar = O.arity theta
      in
        ?todo
      end

    and elabFunctionType rxtail =       
      let
        fun go rxs : abt elab = 
          case rxs of 
             [] =>
             throw @@ Fail "elabFunctionType"
           | [rx] =>
             elabAbt rx
           | Rx.NODE {con = Rx.TYPED_CELL (xs, rxty), ...} :: rxs =>
             goPiVars rxs (?todo) xs
           | rxty :: rxs => ?todo

        and goVars rxs rxty xs = 
          case rxty of 
             Rx.NODE {con = Rx.ATOM "dim", ...} =>
             goLineVars rxs xs
           | _ =>
             elabAbt rxty >>= (fn ty => 
               goPiVars rxs ty xs)

        and goLineVars rxs = 
          fn [] => go rxs
           | x::xs =>
             bindVar (x, O.EXP) (fn x' => 
               goLineVars rxs xs >>= (fn tm => 
                 ret @@ O.LINE $$ [[x'] \ tm]))

        and goPiVars rxs ty = 
          fn [] => go rxs
           | x::xs => 
             bindVar (x, O.EXP) (fn x' =>
               goPiVars rxs ty xs >>= (fn tm => 
                 ret @@ O.FUN $$ [[] \ ty, [x'] \ tm]))
      in
        go rxtail
      end

    and elabLambda rxtail =
      let
        fun go rxs : abt elab = 
          case rxs of 
             [] => throw @@ Fail "elabLambda"
           | [rx] =>
             elabAbt rx                          
           | Rx.NODE {con = Rx.BIND_CELL xs,...} :: rxs => 
             goVars rxs xs

        and goVars rxs : string list -> abt elab = 
          fn [] => go rxs
           | x::xs =>
             bindVar (x, O.EXP) (fn x' => 
               goVars rxs xs >>= (fn tm => 
                 ret @@ O.LAM $$ [[x'] \ tm]))
      in
        go rxtail
      end

    and elabBinder (x, tau) rx = 
      bindVar (x, tau) (fn x' =>
        elabAbt rx >>= (fn tm =>
          ret @@ [x'] \ tm))

    and elabCoe rxtail = 
      case rxtail of 
         [rxdim0, Rx.NODE {con = Rx.ATOM "~>",...}, rxdim1, Rx.NODE {con = Rx.BIND_CELL [x],...}, rxty, rxtm] =>
         elabAbt rxdim0 >>= (fn dim0 => 
           elabAbt rxdim1 >>= (fn dim1 =>
             elabBinder (x, O.EXP) rxty >>= (fn ty => 
               elabAbt rxtm >>= (fn tm => 
                 ret @@ O.COE $$ [[] \ dim0, [] \ dim1, ty, [] \ tm]))))
       | _ => throw @@ Fail "elabCoe"

    and elabFunApp rxtail =
      let
        fun go hd =
          fn [] => ret hd
           | rx::rxs =>
             elabAbt rx >>= (fn tm =>
               go (O.APP $$ [[] \ hd, [] \ tm]) rxs)
      in
        case rxtail of 
           [] => throw @@ Fail "elabFunApp"
         | rx::rxs =>
           elabAbt rx >>= (fn hd =>
             go hd rxs)
      end

    and elabDimApp rxtail =
      let
        fun go hd =
          fn [] => ret hd
           | rx::rxs =>
             elabAbt rx >>= (fn tm =>
               go (O.DIM_APP $$ [[] \ hd, [] \ tm]) rxs)
      in
        case rxtail of 
           [] => throw @@ Fail "elabDimApp"
         | rx::rxs =>
           elabAbt rx >>= (fn hd =>
             go hd rxs)
      end      


    and elabList rxhead rxtail =
      let
        val Rx.NODE {con = conHead, pos} = rxhead
      in
        case conHead of 
           Rx.ATOM "->" => elabFunctionType rxtail
         | Rx.ATOM "*" => elabProductType rxtail
         | Rx.ATOM "record" => elabRecordType rxtail
         | Rx.ATOM "tuple" => elabTuple rxtail
         | Rx.ATOM "lam" => elabLambda rxtail
         | Rx.ATOM "coe" => elabCoe rxtail
         | Rx.ATOM "$" => elabFunApp rxtail
         | Rx.ATOM "@" => elabDimApp rxtail         
         | Rx.ATOM opid =>
           elabOperator pos opid >>= (fn theta => 
             elabOpApp theta rxtail)
         | _ => ?todo
      end
           
  end







  type elab_cmd = env -> icmd * cty
  type elab_val = env -> ivalue * vty

  fun elabBind (elab1 : elab_cmd, nm, elab2 : elab_cmd) : elab_cmd = fn env =>
    let
      val (cmd1, Ty.UP vty1) = elab1 env
      val (cmd2, cty2) = elab2 (R.extendId env nm vty1)
    in
      (ISyn.BIND (cmd1, nm, cmd2), cty2)
    end

  fun elabMatchMetas (elabv, Xs, elabc) env =
    let
      val (v', Ty.METAS vls) = elabv env
      val (psi, env') = R.extendMetas env (Xs, vls)
      val (cmd', cty) = elabc env'
    in
      (ISyn.MATCH_METAS (v', List.map #1 psi, cmd'), cty)
    end

  fun elabFresh vls : elab_cmd = fn env =>
    (ISyn.FRESH vls, Ty.UP @@ Ty.METAS @@ List.map #2 vls)


  fun elabVar (nm : MlId.t) : elab_val = fn env =>
    (ISyn.VAR nm, R.lookupId env NONE nm)

  fun elabNu (psi, elabc : elab_cmd) : elab_cmd =
    let
      val (Xs, vls) = ListPair.unzip psi
      val hintedVls = ListPair.mapEq (fn (X, vl) => (SOME X, vl)) (Xs, vls)
      val xpsi = MlId.new ()
    in
      elabBind (elabFresh hintedVls, xpsi, elabMatchMetas (elabVar xpsi, Xs, elabc))
    end

  fun elabThunk (elabc : elab_cmd) : elab_val = fn env =>
    let
      val (cmd, cty) = elabc env
    in
      (ISyn.THUNK cmd, Ty.DOWN cty)
    end

  fun elabTerm (ast, tau) : elab_val = fn env =>
    (ISyn.TERM @@ elabAst env (ast, tau), Ty.TERM tau)

  fun elabMetas psi : elab_val = fn env =>
    let
      val psi' = (List.map (fn (X, vl) => R.lookupMeta env NONE X) psi)
      val vls = List.map #2 psi'
    in
      (ISyn.METAS psi', Ty.METAS vls)
    end

  fun elabAbs (elabvpsi : elab_val, elabv : elab_val) : elab_val = fn env =>
    let
      val (vpsi, Ty.METAS vls) = elabvpsi env
      val (v, vty) = elabv env
    in
      (ISyn.ABS (vpsi, v), Ty.ABS (vls, vty))
    end

  fun elabRet (elabv : elab_val) : elab_cmd = fn env =>
    let
      val (v, vty) = elabv env
    in
      (ISyn.RET v, Ty.UP vty)
    end

  (* Expects a multitactic in 'script' *)
  fun refineSequents (name, sequents : Sequent.jdg list, script : RedPrlAbt.abt) : icmd * cty = 
    let
      val tele = List.foldl (fn (jdg,psi) => Lcf.Tl.snoc psi (Metavar.new ()) (Lcf.I.ret jdg)) Lcf.Tl.empty sequents
      val evd = Tm.checkb (Tm.\ ([], Tm.$$ (O.AX, [])), ([], O.EXP))
      val state = Lcf.|> (tele, evd)
    in
      (ISyn.REFINE_MULTI (name, state, script), Ty.UP Ty.ONE)
    end

  fun refineSequent (name, sequent : Sequent.jdg, script : RedPrlAbt.abt) : icmd * cty =
    let
      val Sequent.>> (_, ajdg) = sequent
    in
      (ISyn.REFINE (name, sequent, script), Ty.UP o Ty.THM @@ AJ.synthesis ajdg)
    end

  fun elabRefine (name, ajdg, script) : elab_cmd = fn env =>
    let
      val ajdg' = elabAtomicJdg env ajdg
      val sequent = Sequent.>> (Sequent.Hyps.empty, ajdg')
      val script' = elabAst env (script, RedPrlSort.TAC)
    in
      refineSequent (name, sequent, script')
    end

  fun elabDef (psi, definiens) : elab_cmd =
    elabNu (psi, elabRet (elabAbs (elabMetas psi, elabTerm definiens)))

  fun elabThm (name, psi, goal, script) : elab_cmd =
    let
      val x = MlId.new ()
    in
      elabNu (psi, elabBind (elabRefine (SOME name, goal, script), x, elabRet @@ elabAbs (elabMetas psi, elabVar x)))
    end

  fun elabDataDecl (name, psi, foo) : elab_cmd =
    let
      (* TODO *)
      val result : elab_val = fn env => (ISyn.DATA_INFO {foo = ()}, Ty.DATA_INFO)
      val resultAbs =
        (* To insert a check a list of sequents against a multitactic, use
            elabBind (fn env => refineSequents (name, sequents, elabAst env (script, RedPrlSort.MTAC)), MlId.fresh "_", ....)

           note that currently you don't have access to the extracts or anything
            - jms
         *)
        elabRet (elabAbs (elabMetas psi, result))
    in
      elabNu (psi, resultAbs)
    end
  
  fun elabMatchThm (elabv : elab_val, xjdg, xtm, elabc : elab_cmd) : elab_cmd = fn env => 
    let
      val (v', ty) = elabv env
      val tau =
        case ty of
          Ty.THM tau => tau
        | _ => Err.raiseError @@ Err.GENERIC [Fpp.text "MATCH_THM applied to non-theorem"]

      val env' = R.extendId env xjdg @@ Ty.TERM RedPrlSort.JDG
      val env'' = R.extendId env' xtm @@ Ty.TERM tau
      val (cmd', cty) = elabc env''
    in
      (ISyn.MATCH_THM (v', xjdg, xtm, cmd'), cty)
    end

  fun elabMatchAbs (elabv : elab_val, xpsi, xv, elabc : elab_cmd) : elab_cmd = fn env =>
    let
      val (v, Ty.ABS (vls, vty)) = elabv env
      val env' = R.extendId env xpsi @@ Ty.METAS vls
      val env'' = R.extendId env' xv vty
      val (cmd, cty) = elabc env''
    in
      (ISyn.MATCH_ABS (v, xpsi, xv, cmd), cty)
    end

  fun elabPrint (pos, elabv : elab_val) : elab_cmd = fn env =>
    (ISyn.PRINT (pos, #1 @@ elabv env), Ty.UP Ty.ONE)


  fun elabExtract (elabv : elab_val) : elab_cmd = 
    let
      val xpsi = MlId.new ()
      val xthm = MlId.new ()
      val xjdg = MlId.new ()
      val xtm = MlId.new ()
    in
      elabMatchAbs (elabv, xpsi, xthm, elabMatchThm (elabVar xthm, xjdg, xtm, elabRet @@ elabAbs (elabVar xpsi, elabVar xtm)))
    end

  fun elabPrintExtract (pos, elabv : elab_val) : elab_cmd =
    let
      val xtm = MlId.new ()
    in
      elabBind (elabExtract elabv, xtm, elabPrint (pos, elabVar xtm))
    end

  val elabAbort : elab_cmd = fn _ => 
    (ISyn.ABORT, Ty.UP Ty.ONE)

  fun elabForce (elabv : elab_val) : elab_cmd = fn env => 
    let
      val (v', vty) = elabv env
    in
      case vty of
         Ty.DOWN cty => (ISyn.FORCE v', cty)
       | _ => Err.raiseError @@ Err.GENERIC [Fpp.text "Expected down-shifted type"]
    end

  fun elabFn (x, vty, elabc : elab_cmd) : elab_cmd = fn env =>
    let
      val env' = R.extendId env x vty
      val (cmd', cty) = elabc env'
    in
      (ISyn.FN (x, vty, cmd'), Ty.FUN (vty, cty))
    end

  fun elabAp (elabc : elab_cmd, elabv : elab_val) : elab_cmd = fn env => 
    let
      val (cmd', cty) = elabc env
    in
      case cty of
         Ty.FUN (vty, cty') =>
         let
           val (v', vty') = elabv env
         in
           if vty = vty' then
             (ISyn.AP (cmd', v'), cty')
           else
             Err.raiseError @@ Err.GENERIC [Fpp.text "Argument type mismatch"]
         end
       | _ => Err.raiseError @@ Err.GENERIC [Fpp.text "Expected function type"]
    end

  fun elabValue value : elab_val =
    case value of
       ESyn.THUNK cmd =>
       elabThunk (elabCmd cmd)

     | ESyn.VAR nm =>
       elabVar nm

     | ESyn.NIL =>
       (fn _ => (ISyn.NIL, Ty.ONE))

     | ESyn.TERM (ast, tau) =>
       elabTerm (ast, tau)

     | ESyn.METAS psi =>
       elabMetas psi

     | ESyn.ABS (vpsi, v) =>
       elabAbs (elabValue vpsi, elabValue v)


  and elabCmd cmd : elab_cmd =
    case cmd of
       ESyn.NU (psi, cmd) =>
       elabNu (psi, elabCmd cmd)

     | ESyn.DEF {arguments, definiens} =>
       elabDef (arguments, definiens)

     | ESyn.TAC {arguments, script} =>
       elabDef (arguments, (script, RedPrlSort.TAC))

     | ESyn.THM {name, arguments, goal, script} =>
       elabThm (name, arguments, goal, script)

     | ESyn.DATA_DECL {name, arguments, foo} =>
       elabDataDecl (name, arguments, foo)

     | ESyn.PRINT_EXTRACT (pos, v) =>
       elabPrintExtract (pos, elabValue v)

     | ESyn.EXTRACT v =>
       elabExtract (elabValue v)

     | ESyn.BIND (cmd1, nm, cmd2) =>
       elabBind (elabCmd cmd1, nm, elabCmd cmd2)

     | ESyn.RET v =>
       elabRet (elabValue v)

     | ESyn.FORCE v =>
       elabForce (elabValue v)

     | ESyn.FN (x, vty, cmd) =>
       elabFn (x, vty, elabCmd cmd)

     | ESyn.AP (cmd, v) =>
       elabAp (elabCmd cmd, elabValue v)

     | ESyn.PRINT (pos, v) =>
       elabPrint (pos, elabValue v)

     | ESyn.REFINE (name, ajdg, script) =>
       elabRefine (name, ajdg, script)

     | ESyn.FRESH vls =>
       elabFresh vls

     | ESyn.MATCH_METAS (v, Xs, cmd) =>
       elabMatchMetas (elabValue v, Xs, elabCmd cmd)

     | ESyn.MATCH_THM (v, xjdg, xtm, cmd) =>
       elabMatchThm (elabValue v, xjdg, xtm, elabCmd cmd)

     | ESyn.MATCH_ABS (v, xpsi, xv, cmd) =>
       elabMatchAbs (elabValue v, xpsi, xv, elabCmd cmd)

     | ESyn.ABORT =>
       elabAbort

end
