module Verifier where

import Language.Java.Syntax
import Language.Java.Pretty
import Z3.Monad
import System.IO.Unsafe

import Folds
import HelperFunctions


-- | Checks wether the negation is unsatisfiable
isTrue :: Exp -> Z3 Bool
isTrue e = isFalse (PreNot e)
            
          
-- | Checks wether the expression is unsatisfiable
isFalse :: Exp -> Z3 Bool
isFalse e = 
    do
        ast <- foldExp expAssertAlgebra e
        assert ast
        result <- check
        solverReset
        case result of
            Unsat -> return True
            _     -> return False
        
-- | Unsafe version of isTrue
unsafeIsTrue :: Exp -> Bool
unsafeIsTrue = unsafePerformIO . evalZ3 . isTrue

-- | Unsafe version of isFalse
unsafeIsFalse :: Exp -> Bool
unsafeIsFalse = unsafePerformIO . evalZ3 . isFalse

stringToBv :: String -> Z3 AST
stringToBv [] = mkIntNum 0 >>= mkInt2bv 8
stringToBv (c:cs) = do
                        c' <- mkIntNum (fromEnum c) >>= mkInt2bv 8
                        cs' <- stringToBv cs
                        mkConcat c' cs'
                        

-- | Defines the convertion from an expression to AST so that Z3 can assert satisfiability
--   This is used to fold expressions generated by the WLP transformer, so not all valid Java expressions need to be handled
expAssertAlgebra :: ExpAlgebra (Z3 AST)
expAssertAlgebra = (fLit, fClassLit, fThis, fThisClass, fInstanceCreation, fQualInstanceCreation, fArrayCreate, fArrayCreateInit, fFieldAccess, fMethodInv, fArrayAccess, fExpName, fPostIncrement, fPostDecrement, fPreIncrement, fPreDecrement, fPrePlus, fPreMinus, fPreBitCompl, fPreNot, fCast, fBinOp, fInstanceOf, fCond, fAssign, fLambda, fMethodRef) where
    fLit lit       = case lit of
                        Int n -> mkInteger n
                        Word n -> mkInteger n
                        Float d -> mkRealNum d
                        Double d -> mkRealNum d
                        Boolean b -> mkBool b
                        Char c -> do sort <- mkIntSort
                                     mkInt (fromEnum c) sort
                        String s -> stringToBv s
                        Null -> do sort <- mkIntSort
                                   mkInt 0 sort
    fClassLit = undefined
    fThis = undefined
    fThisClass = undefined
    fInstanceCreation = undefined
    fQualInstanceCreation = undefined
    fArrayCreate = undefined
    fArrayCreateInit = undefined
    fFieldAccess fieldAccess    = case fieldAccess of
                                    PrimaryFieldAccess e id         -> case e of
                                                                        InstanceCreation _ t args _ -> undefined
                                                                        _ -> undefined
                                    SuperFieldAccess id             -> mkStringSymbol (prettyPrint (Name [id])) >>= mkIntVar
                                    ClassFieldAccess (Name name) id -> mkStringSymbol (prettyPrint (Name (name ++ [id]))) >>= mkIntVar
    fMethodInv invocation       = case invocation of
                                    MethodCall (Name [Ident "*length"]) [a, (Lit (Int n))] -> case a of
                                                                                                    ArrayCreate t exps dim          -> foldExp expAssertAlgebra (if fromEnum n < length exps then (exps !! fromEnum n) else Lit (Int 0))
                                                                                                    ArrayCreateInit t dim arrayInit -> mkInteger 0
                                                                                                    _                               -> error "length of non-array"
                                    _ -> error (prettyPrint invocation)
    fArrayAccess arrayIndex     = case arrayIndex of
                                    ArrayIndex (ArrayCreate t _ _) _ -> foldExp expAssertAlgebra (getInitValue t)
                                    ArrayIndex (ArrayCreateInit t _ _) _ -> foldExp expAssertAlgebra (getInitValue t)
                                    ArrayIndex e _ -> foldExp expAssertAlgebra e
    fExpName name   = do
                        symbol <- mkStringSymbol (prettyPrint name)
                        mkIntVar symbol
    fPostIncrement = undefined
    fPostDecrement = undefined
    fPreIncrement = undefined
    fPreDecrement = undefined
    fPrePlus e = e
    fPreMinus e = do
                    ast <- e
                    zero <- mkInteger 0
                    mkSub [zero, ast]
    fPreBitCompl = undefined
    fPreNot e = e >>= mkNot
    fCast = undefined
    fBinOp e1 op e2    = case op of
                            Mult -> do
                                      ast1 <- e1
                                      ast2 <- e2
                                      mkMul [ast1, ast2]
                            Div -> do
                                      ast1 <- e1
                                      ast2 <- e2
                                      mkDiv ast1 ast2
                            Rem -> do
                                      ast1 <- e1
                                      ast2 <- e2
                                      mkRem ast1 ast2
                            Add -> do
                                      ast1 <- e1
                                      ast2 <- e2
                                      mkAdd [ast1, ast2]
                            Sub -> do
                                      ast1 <- e1
                                      ast2 <- e2
                                      mkSub [ast1, ast2]
                            LShift -> do
                                      ast1 <- e1
                                      ast2 <- e2
                                      mkBvshl ast1 ast2
                            RShift -> do
                                      ast1 <- e1
                                      ast2 <- e2
                                      mkBvashr ast1 ast2
                            RRShift -> do
                                      ast1 <- e1
                                      ast2 <- e2
                                      mkBvlshr ast1 ast2
                            LThan -> do
                                      ast1 <- e1
                                      ast2 <- e2
                                      mkLt ast1 ast2
                            GThan -> do
                                      ast1 <- e1
                                      ast2 <- e2
                                      mkGt ast1 ast2
                            LThanE -> do
                                      ast1 <- e1
                                      ast2 <- e2
                                      mkLe ast1 ast2
                            GThanE -> do
                                      ast1 <- e1
                                      ast2 <- e2
                                      mkGe ast1 ast2
                            Equal -> do
                                      ast1 <- e1
                                      ast2 <- e2
                                      mkEq ast1 ast2
                            NotEq -> do
                                      ast1 <- e1
                                      ast2 <- e2
                                      eq <- mkEq ast1 ast2
                                      mkNot eq
                            And-> do
                                      ast1 <- e1
                                      ast2 <- e2
                                      mkAnd [ast1, ast2]
                            Or -> do
                                      ast1 <- e1
                                      ast2 <- e2
                                      mkOr [ast1, ast2]
                            Xor -> do
                                      ast1 <- e1
                                      ast2 <- e2
                                      mkXor ast1 ast2
                            CAnd -> do
                                      ast1 <- e1
                                      ast2 <- e2
                                      mkAnd [ast1, ast2]
                            COr -> do
                                      ast1 <- e1
                                      ast2 <- e2
                                      mkOr [ast1, ast2]
    fInstanceOf = undefined
    fCond g e1 e2       = do
                            astg <- (g >>= mkNot)
                            assert astg
                            result <- check
                            solverReset 
                            case result of
                                Sat     -> e2
                                Unsat   -> e1
                                _ -> error "can't evaluate if-condition"
    fAssign = undefined
    fLambda = undefined
    fMethodRef = undefined