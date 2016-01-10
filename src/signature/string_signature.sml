structure StringSignatureData =
struct
  type term = string
  type goal = string
  type symbol = string
  type sort = string
  type metavariable = string
  type valence = string

  type symbols = (symbol * sort) list
  type arguments = (metavariable * valence) list

  type def =
    {parameters : symbols,
     arguments : arguments,
     sort : sort,
     definiens : term}

  type tac =
    {parameters : symbols,
     arguments : arguments,
     script : term}

  type thm =
    {parameters : symbols,
     arguments : arguments,
     goal : term,
     script : term}

  datatype decl =
      DEF of def
    | TAC of tac
    | THM of thm

  (* A signature / [sign] is a telescope of declarations. *)
  type sign = decl StringTelescope.telescope
end

structure StringSignature : SIGNATURE = StringSignatureData
