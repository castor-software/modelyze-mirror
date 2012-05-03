(*
Modeling Kernel Language (MKL) toolchain
Copyright (C) 2010-2011 David Broman

MKL toolchain is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

MKL toolchain is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with MKL toolchain.  If not, see <http://www.gnu.org/licenses/>.
*)

open Ustring.Op
open Utils
open Ast
open Message
open Info
open Printf
exception Mkl_type_error of Message.message

let rec meet ty_a ty_b = 
  match ty_a,ty_b with
    | ty,TyDyn(_,_) -> ty
    | TyDyn(_,_),ty -> ty
    | TyBool(fi,_),TyBool(_,_) -> TyBool(fi,0)
    | TyInt(fi,_),TyInt(_,_) -> TyInt(fi,0)
    | TyReal(fi,_),TyReal(_,_) -> TyReal(fi,0)
    | TyString(fi,_),TyString(_,_) -> TyString(fi,0)
    | TyArrow(fi,_,ty1,ty2), TyArrow(_,_,ty3,ty4) ->
        TyArrow(fi,0,meet ty1 ty3, meet ty2 ty4)
    | TyUnit(fi,_),TyUnit(_,_) -> TyUnit(fi,0)
    | TyList(fi,_,ty1),TyList(_,_,ty2) -> 
        TyList(fi,0,meet ty1 ty2)
    | TyTuple(fi,_,tys1),TyTuple(_,_,tys2) -> 
        TyTuple(fi,0,List.map2 meet tys1 tys2)
    | TySym(fi,_,ty1),TySym(_,_,ty2) -> 
        TySym(fi,0,meet ty1 ty2)
    | TySymData(fi,_,tyid1,id),TySymData(_,_,tyid2,_) 
        when tyid1 = tyid2 -> TySymData(fi,0,tyid1,id)
    | TyArray(fi,_,ty1),TyArray(_,_,ty2) -> 
        TyArray(fi,0,meet ty1 ty2)
    | TyMap(fi,_,ty1,ty2), TyMap(_,_,ty3,ty4) ->
        TyMap(fi,0,meet ty1 ty3, meet ty2 ty4)
    | TySet(fi,_,ty1),TySet(_,_,ty2) -> 
        TySet(fi,0,meet ty1 ty2)
    | TyDAESolver(fi,_),TyDAESolver(_,_) -> TyDAESolver(fi,0)
    | _ , _ -> failwith "Meet error. Should not happen."

let rec consistent ty_a ty_b = 
  match ty_a,ty_b with
    | ty,TyDyn(_,_) -> true
    | TyDyn(_,_),ty -> true
    | TyBool(fi,_),TyBool(_,_) -> true
    | TyInt(fi,_),TyInt(_,_) -> true
    | TyReal(fi,_),TyReal(_,_) -> true
    | TyString(fi,_),TyString(_,_) -> true
    | TyArrow(fi,_,ty1,ty2), TyArrow(_,_,ty3,ty4) ->
        consistent ty1 ty3 && consistent ty2 ty4
    | TyUnit(fi,_),TyUnit(_,_) -> true
    | TyList(fi,_,ty1),TyList(_,_,ty2) -> 
        consistent ty1 ty2
    | TyTuple(fi,_,tys1),TyTuple(_,_,tys2) -> 
        List.for_all2 consistent tys1 tys2
    | TySym(fi,_,ty1),TySym(_,_,ty2) -> 
        consistent ty1 ty2
    | TySymData(fi,_,tyid1,id),TySymData(_,_,tyid2,_) 
        when tyid1 = tyid2 -> true
    | TyArray(fi,_,ty1),TyArray(_,_,ty2) -> 
        consistent ty1 ty2
    | TyMap(fi,_,ty1,ty2), TyMap(_,_,ty3,ty4) ->
        consistent ty1 ty3 && consistent ty2 ty4
    | TySet(fi,_,ty1),TySet(_,_,ty2) -> 
        consistent ty1 ty2
    | TyDAESolver(fi,_),TyDAESolver(_,_) -> true
    | _ , _ ->  false

(* Checks if 'ty' is a symbol type. If so, 'e' is returned, else 'e' is lifted. *)
let lift_expr e ty = 
  if consistent ty (TySym(NoInfo,0,TyDyn(NoInfo,0))) 
  then e 
  else TmLift(ty_info ty,0,e,ty)

(* Checks if 'ty' is a symbol type. If so, returns 'ty', else makes 
   it a symbol type. *)
let lift_type ty =
  if consistent ty (TySym(NoInfo,0,TyDyn(NoInfo,0))) 
  then ty
  else TySym(ty_info ty,0,ty)

let lift_branch_cases e1 ty1 e2 ty2 =
  if consistent ty1 ty2
  then (meet ty1 ty2, e1, e2)
  else (meet (lift_type ty1) (lift_type ty2), lift_expr e1 ty1, lift_expr e2 ty2)

(* Symbolic dynamic type *)
let ty_symdyn = TySym(NoInfo,0,TyDyn(NoInfo,0))

let rec tylst_equiv tylst1 tylst2 = List.combine tylst1 tylst2 
   |> List.fold_left (fun inp (ty1,ty2) -> ty_equiv ty1 ty2) true

let rec ty_mono ty = true  (* should be removed *)
	
let rec mk_letenv plst l env =
  match plst with
    | [] -> env
    | (x,ty)::res -> (x,ty)::(mk_letenv res l env)

let ty_ismodel ty = 
  match ty with
    | TySym(_,_,_) -> true
    | _ -> false

let mk_tymodel ty =
  TySym(ty_info ty,ty_lev ty,ty)

	
let check_istype_array fi l ty_ar =
  match ty_ar with
    | TyArray(_,l',ty) when l = l' -> ty
    | _ -> raise (Mkl_type_error(TYPE_EXPECTED_ARRAY_TYPE,ERROR,fi,[pprint_ty ty_ar]))

let check_istype_map fi l ty_ma =
  match ty_ma with
    | TyMap(_,l',ty1,ty2) when l = l' -> (ty1,ty2)
    | _ -> raise (Mkl_type_error(TYPE_EXPECTED_MAP_TYPE,ERROR,fi,[pprint_ty ty_ma]))

let check_istype_set fi l ty_set =
  match ty_set with
    | TySet(_,l',ty) when l = l' -> ty
    | _ -> raise (Mkl_type_error(TYPE_EXPECTED_SET_TYPE,ERROR,fi,[pprint_ty ty_set]))

let check_istype_daesolver fi l ty_daesolver =
  match ty_daesolver with
    | TyDAESolver(_,l') when l = l' -> ()
    | _ -> raise (Mkl_type_error(TYPE_EXPECTED_DAESOLVER_TYPE,ERROR,fi,[pprint_ty ty_daesolver]))
        
let check_istype_int fi l ty_int =
  match ty_int with 
    | TyInt(_,l') when l = l' -> ()
    | _ -> raise (Mkl_type_error(TYPE_EXPECTED_INT_TYPE,ERROR,fi,[pprint_ty ty_int; ustring_of_int l]))

let check_istype_real fi l ty_real =
  match ty_real with 
    | TyReal(_,l') when l = l' -> ()
    | _ -> raise (Mkl_type_error(TYPE_EXPECTED_REAL_TYPE,ERROR,fi,[pprint_ty ty_real; ustring_of_int l]))

let check_istype_resroot fi l ty_residual =
   let tyexp = TyArrow(fi,l,TyReal(fi,l),
           TyArrow(fi,l,TyArray(fi,l,TyReal(fi,l)),
               TyArrow(fi,l,TyArray(fi,l,TyReal(fi,l)), TyList(fi,l,TyReal(fi,l))))) in
   if not (consistent tyexp ty_residual) then
        raise (Mkl_type_error(TYPE_EXPECTED_RESROOT_TYPE,ERROR,fi,[pprint_ty tyexp; pprint_ty ty_residual]))

(*     
let check_arg_type_consistency fi ty' ty_elem =
  if consistent ty' ty_elem then meet ty' ty_elem
  else raise (Mkl_type_error(TYPE_APP_ARG_MISMATCH,ERROR,fi,[pprint_ty ty'; pprint_ty ty_elem]))
*)

let check_and_lift_arg_type_consistency fi e1 elem_ty container_ty =
  if consistent elem_ty container_ty then (meet elem_ty container_ty, e1)
  else if consistent (TySym(NoInfo,0,elem_ty)) container_ty 
  then (meet (TySym(NoInfo,0,elem_ty)) container_ty, TmLift(NoInfo,0,e1,elem_ty))
  else raise (Mkl_type_error(TYPE_APP_ARG_MISMATCH,ERROR,fi,[pprint_ty elem_ty; pprint_ty container_ty]))



let rec typeof_array_op fi l op ts env  =
  match op,ts with
    | ArrayOpLength,[ar] -> 
        let (ty_ar,ar') = typeof env  ar in
        let _ = check_istype_array (tm_info ar) l ty_ar in
          (TyInt(fi,l),[ar'])
    | ArrayOpMake,[len;elem] ->  
        let (ty_len,len') = typeof env  len in
        let (ty_elem,elem') = typeof env  elem in
          check_istype_int (tm_info len)l ty_len;
          (TyArray(fi,l,ty_elem),[len';elem'])
    | ArrayOpGet,[ar;pos] -> 
        let (ty_ar,ar') = typeof env  ar in
        let (ty_pos,pos') = typeof env  pos in
        let ty' = check_istype_array (tm_info ar) l ty_ar in
          check_istype_int (tm_info pos) l ty_pos;
          (ty',[ar';pos'])
    | ArrayOpSet,[ar;pos;elem] ->  
        let (ty_ar,ar') = typeof env  ar in
        let (ty_pos,pos') = typeof env  pos in
        let (ty_elem,elem') = typeof env  elem in
        let ty' = check_istype_array (tm_info ar) l ty_ar in
          check_istype_int (tm_info pos) l ty_pos;
          let (ty_elem',elem'') = check_and_lift_arg_type_consistency (tm_info elem) elem' ty' ty_elem in
            (TyUnit(fi,l),[ar';pos';elem''])
    | _ -> raise (Mkl_type_error
	            (TYPE_UNEXPECTED_NO_ARGS,ERROR,fi,
                     [ustring_of_int (List.length ts)]))

and typeof_map_op fi l op ts env  =
  match op,ts with
    | MapOpSize,[ma] -> 
        let (ty_ma,ma') = typeof env  ma in
        let _ = check_istype_map (tm_info ma) l ty_ma in
          (TyInt(fi,l),[ma'])
    | MapOpEmpty,[] -> 
        (TyMap(fi,l,TyDyn(fi,l),TyDyn(fi,l)),[])
    | MapOpAdd,[key;value;ma] ->
        let (ty_key,key') = typeof env  key in
        let (ty_value,value') = typeof env  value in
        let (ty_ma,ma') = typeof env  ma in
        let (ty_ma1,ty_ma2) = check_istype_map (tm_info ma) l ty_ma in
        let (ty_key',key'') = check_and_lift_arg_type_consistency (tm_info key) key' ty_key ty_ma1 in
        let (ty_value', value'') = check_and_lift_arg_type_consistency (tm_info value) value' ty_value ty_ma2 in
          (TyMap(fi,l,ty_key',ty_value'),[key'';value'';ma'])
    | MapOpFind,[key;ma] ->
        let (ty_key,key') = typeof env  key in
        let (ty_ma,ma') = typeof env ma in
        let (ty_ma1,ty_ma2) = check_istype_map (tm_info ma) l ty_ma in
        let (ty_key',key'') = check_and_lift_arg_type_consistency (tm_info key) key' ty_key ty_ma1 in
          (ty_ma2,[key'';ma'])
    | MapOpMem,[key;ma] ->
        let (ty_key,key') = typeof env  key in
        let (ty_ma,ma') = typeof env  ma in
        let (ty_ma1,ty_ma2) = check_istype_map (tm_info ma) l ty_ma in
        let (ty_key',key'') = check_and_lift_arg_type_consistency (tm_info key) key' ty_key ty_ma1 in
          (TyBool(fi,l),[key'';ma'])
    | MapOpRemove,[key;ma] ->
        let (ty_key,key') = typeof env  key in
        let (ty_ma,ma') = typeof env  ma in
        let (ty_ma1,ty_ma2) = check_istype_map (tm_info ma) l ty_ma in
        let (ty_key',key'') = check_and_lift_arg_type_consistency (tm_info key) key' ty_key ty_ma1 in
          (TyMap(fi,l,ty_key',ty_ma2),[key'';ma'])
    | MapOpToList,[ma] ->
        let (ty_ma,ma') = typeof env  ma in
        let (ty_ma1,ty_ma2) = check_istype_map (tm_info ma) l ty_ma in
        let ty_lst = TyList(fi,l,TyTuple(fi,l,[ty_ma1;ty_ma2])) in
          (ty_lst,[ma'])
    | _ -> raise (Mkl_type_error
	            (TYPE_UNEXPECTED_NO_ARGS,ERROR,fi,
                     [ustring_of_int (List.length ts)]))


and typeof_set_op fi l op ts env  =
  match op,ts with
    | SetOpSize,[set] -> 
        let (ty_set,set') = typeof env  set in
        let _ = check_istype_set (tm_info set) l ty_set in
          (TyInt(fi,l),[set'])
    | SetOpEmpty,[] -> 
        (TySet(fi,l,TyDyn(fi,l)),[])
    | SetOpAdd,[key;set] ->
        let (ty_key,key') = typeof env  key in
        let (ty_set,set') = typeof env  set in
        let ty_setkey = check_istype_set (tm_info set) l ty_set in
        let (ty_key',key'') = check_and_lift_arg_type_consistency (tm_info set) key' ty_key ty_setkey in
          (TySet(fi,l,ty_key'),[key'';set'])
    | SetOpMem,[key;set] ->
        let (ty_key,key') = typeof env  key in
        let (ty_set,set') = typeof env  set in
        let ty_setkey = check_istype_set (tm_info set) l ty_set in
        let (ty_key',key'') = check_and_lift_arg_type_consistency (tm_info key) key' ty_key ty_setkey in
          (TyBool(fi,l),[key'';set'])
    | SetOpRemove,[key;set] ->
        let (ty_key,key') = typeof env  key in
        let (ty_set,set') = typeof env  set in
        let ty_setkey = check_istype_set (tm_info set) l ty_set in
        let (ty_key',key'') = check_and_lift_arg_type_consistency (tm_info set) key' ty_key ty_setkey in
          (TySet(fi,l,ty_key'),[key'';set'])
    | SetOpToList,[set] ->
        let (ty_set,set') = typeof env  set in
        let ty_setkey = check_istype_set (tm_info set) l ty_set in
        let ty_lst = TyList(fi,l,ty_setkey) in
          (ty_lst,[set'])
    | _ -> raise (Mkl_type_error
	            (TYPE_UNEXPECTED_NO_ARGS,ERROR,fi,
                     [ustring_of_int (List.length ts)]))

and typeof_daesolver_op fi l op ts env  = 
  match op,ts with
    | DAESolverOpMake,[ar_yy;ar_yp;ar_id;tmres] ->
        let (ty_ar_yy,ar_yy') = typeof env  ar_yy in
        let (ty_ar_yp,ar_yp') = typeof env  ar_yp in
        let (ty_ar_id,ar_id') = typeof env  ar_id in
        let (ty_tmres,tmres') = typeof env  tmres in
        let ty_yy' = check_istype_array (tm_info ar_yy) l ty_ar_yy in
        let ty_yp' = check_istype_array (tm_info ar_yp) l ty_ar_yp in
        let ty_id' = check_istype_array (tm_info ar_id) l ty_ar_id in
          check_istype_real (tm_info ar_yy) l ty_yy';
          check_istype_real (tm_info ar_yp) l ty_yp';
          check_istype_real (tm_info ar_id) l ty_id';
          check_istype_resroot (tm_info tmres) l ty_tmres;
          (TyDAESolver(fi,l),[ar_yy';ar_yp';ar_id';tmres'])

    | DAESolverOpMakeHybrid,[time;ar_yy;ar_yp;ar_id;tmres;tmroot] ->
        let (ty_time,time') = typeof env  time in
        let (ty_ar_yy,ar_yy') = typeof env  ar_yy in
        let (ty_ar_yp,ar_yp') = typeof env  ar_yp in
        let (ty_ar_id,ar_id') = typeof env  ar_id in
        let (ty_tmres,tmres') = typeof env  tmres in
        let (ty_tmroot,tmroot') = typeof env  tmroot in
        let ty_yy' = check_istype_array (tm_info ar_yy) l ty_ar_yy in
        let ty_yp' = check_istype_array (tm_info ar_yp) l ty_ar_yp in
        let ty_id' = check_istype_array (tm_info ar_id) l ty_ar_id in
          check_istype_real (tm_info time) l ty_time;
          check_istype_real (tm_info ar_yy) l ty_yy';
          check_istype_real (tm_info ar_yp) l ty_yp';
          check_istype_real (tm_info ar_id) l ty_id';
          check_istype_resroot (tm_info tmres) l ty_tmres;
          check_istype_resroot (tm_info tmroot) l ty_tmroot;
          (TyDAESolver(fi,l),[time';ar_yy';ar_yp';ar_id';tmres';tmroot'])

    | DAESolverOpStep,[time;sun] ->
        let (ty_time,time') = typeof env  time in
          check_istype_real (tm_info time) l ty_time;
          let (ty_sun,sun') = typeof env  sun in
            check_istype_daesolver (tm_info sun) l ty_sun;
            (ty_time,[time';sun'])

    | DAESolverOpReinit,[sun] ->
        let (ty_sun,sun') = typeof env  sun in
          check_istype_daesolver (tm_info sun) l ty_sun;
          (TyUnit(NoInfo,l),[sun'])

    | DAESolverOpClose,[sun] ->
        let (ty_sun,sun') = typeof env  sun in
          check_istype_daesolver (tm_info sun) l ty_sun;
          (TyUnit(NoInfo,l),[sun'])

    | DAESolverOpRoots,[sun] ->
        let (ty_sun,sun') = typeof env  sun in
          check_istype_daesolver (tm_info sun) l ty_sun;
          (TyArray(NoInfo,l,TyInt(NoInfo,l)),[sun'])

    | _ -> raise (Mkl_type_error
	            (TYPE_UNEXPECTED_NO_ARGS,ERROR,fi,
                     [ustring_of_int (List.length ts)]))

and typeof env t =
  match t with
    | TmVar(fi,x) -> ( 
        try let ty1 = List.assoc x env in (ty1,TmVar(fi,x))
	with Not_found -> (
          raise (Mkl_type_error (TYPE_VAR_NOT_DEFINED,ERROR,fi,[Symtbl.get x]))))
    | TmLam(fi,l,x,ty1,t2) ->
        let (ty2,t2') = typeof ((x,ty1)::env)  t2 in
	  (TyArrow(NoInfo,l,ty1,ty2),TmLam(fi,l,x,ty1,t2'))
    | TmFix(fi,l,t) ->
	let (ty,t') = typeof env  t in
	  begin match ty with
	    | TyArrow(fi,l1,ty1,ty2) -> 
		if not (consistent ty1 ty2) then 
		  raise (Mkl_type_error(TYPE_FIX_MISMATCH,ERROR,tm_info t, [pprint_ty ty1; pprint_ty ty2]))
		else (ty1,TmFix(fi,l,t'))
	    | _ -> raise (Mkl_type_error(TYPE_FIX_ERROR,ERROR,tm_info t,[]))
	  end
    | TmApp(fi,_,e1,e2,fs)  -> 
        let (ty1,e1') = typeof env e1 in
        let (ty2,e2') = typeof env e2 in
          (match ty1,ty2 with
               (* L-APP1 *) 
             | TyArrow(fi2,_,ty11,ty12),ty2 
                 when consistent ty11 ty2
                   -> (ty12,TmApp(fi,0,e1',e2',fs))
                 (* L-APP2 *)
             | TyDyn(fi2,_),ty2 
                  -> (TyDyn(fi2,0), TmApp(fi,0,e1',e2',fs))
                 (* L-APP3 *) 
             | TyArrow(fi2,_,ty11,ty12),ty2 
                 when consistent ty11 (TySym(NoInfo,0,ty2))
                   -> (ty12,TmApp(fi,0,e1',TmLift(NoInfo,0,e2',ty2),fs))
                 (* L-APP4 *)
             | TyArrow(fi2,_,ty11,ty12),ty2 
                  when (consistent (TySym(NoInfo,0,ty11)) ty2)
                   -> (TySym(ty_info ty12,0,ty12), TmSymApp(fi,0,TmLift(NoInfo,0,e1',ty1),e2'))  
                 (* L-APP5 *)
             | TySym(fi2,_,TyDyn(fi3,_)),ty2 
                 -> let e2'' = lift_expr e2' ty2 in
                   (TySym(fi2,0,TyDyn(fi3,0)), TmSymApp(fi,0,e1',e2''))
                 (* L-APP6 *)
             | TySym(fi2,_,TyArrow(fi3,_,ty11,ty12)),ty2
                 when consistent (TySym(NoInfo,0,ty11)) (lift_type ty2) 
                   -> let e2'' = lift_expr e2' ty2 in
                     (TySym(ty_info ty12,0,ty12), TmSymApp(fi,0,e1',e2''))
             | TyArrow(fi2,_,ty11,ty12),ty2 -> 
                 raise (Mkl_type_error(TYPE_APP_ARG_MISMATCH,ERROR,tm_info e2,[pprint_ty ty11; pprint_ty ty2]))
             | ty1,ty2 -> raise (Mkl_type_error(TYPE_APP_ABS_MISMATCH,ERROR,
                                                tm_info e2,[pprint_ty ty1; pprint_ty ty2]))
          )              
    | TmLet(fi,_,x,ty,plst,e1,e2,recu) ->
	let t1_env = mk_letenv plst 0 env in
        let (ty1,e1') = 
          (match (ty,recu) with
	     | (None,true) -> raise (Mkl_type_error(TYPE_LET_REC_MISS_RET_TYPE,ERROR,fi,[]))
	     | (Some ty1def,recu) -> 
		 let tyvar = Ast.mk_lettype plst 0 ty1def in
		 let (ty1,t1') = if recu then typeof ((x,tyvar)::t1_env) e1 else typeof t1_env e1 
                 in                    
                   if consistent ty1 ty1def then
		     (ty1def,t1')
                   else if consistent ty1def (TySym(NoInfo,0,ty1)) then
                     (ty1def, TmLift(NoInfo,0,t1',ty1))
                   else
		     raise (Mkl_type_error(TYPE_LET_TYPE_DEF_MISMATCH, ERROR,fi,[pprint_ty ty1; pprint_ty ty1def]))
	     | (None,false) -> typeof t1_env  e1)
        in
	let tyvar = Ast.mk_lettype plst 0 ty1 in
	let (ty2,e2') = typeof ((x,tyvar)::env) e2 in
	  (ty2,TmLet(fi,0,x,Some ty1,plst,e1',e2',recu))                    
    | TmIf(fi,l,e1,e2,e3) ->
        let (ty1,e1') = typeof env e1 in
        let (ty2,e2') = typeof env e2 in
        let (ty3,e3') = typeof env e3 in
          if not (consistent ty1 (TyBool(NoInfo,0))) then
            raise (Mkl_type_error(TYPE_MISMATCH_IF_GUARD,ERROR,tm_info e1, [pprint_ty (TyBool(NoInfo,l)); pprint_ty ty1]))
          else if not (consistent (lift_type ty2) (lift_type ty3)) then
            raise (Mkl_type_error(TYPE_IF_EXP_DIFF_TYPE,ERROR,fi,[pprint_ty ty2; pprint_ty ty3]))
          else
            let (ty4,e2'',e3'') = lift_branch_cases e2' ty2 e3' ty3 in
              (ty4, TmIf(fi,0,e1',e2'',e3''))
    | TmConst(fi,l,c) as tt -> (deltatype fi c l,tt)
    | TmList(fi,l,ts) ->
	(match ts with
	   | [] -> assert false
	   | t::_ -> let (ty',t') = typeof env  t in 
               typeof env  (List.fold_left 
			      (fun a t -> TmCons(tm_info t,l,t,a)) 
		              (TmNil(fi,l,ty')) ts))
    | TmMatch(fi,l,t,cases) -> assert false
    | TmSym(fi,l,u,ty) -> failwith "Only in the internal language."
    | TmNu(fi,l,u,ty1,t2) ->
	if not (ty_ismodel ty1) then
	  raise (Mkl_type_error(TYPE_NU_LET_NOT_MODELTYPE,ERROR,
				ty_info ty1,[pprint_ty ty1]))
        else
          let (ty2,t2') = typeof ((u,ty1)::env)  t2 in
	    (ty2,TmNu(fi,l,u,ty1,t2'))
    | TmSymApp(fi,l,t1,t2) -> failwith "Only in internal language."
    | TmLift(fi,l,t,_) -> failwith "Only in internal language."
    | TmCase(fi,l,e1,p,e2,e3) ->
        let (ty1,e1') = typeof env e1 in
        let (ty3,e3') = typeof env e3 in
          if consistent ty_symdyn ty1 then 
            (match p with
                 (* L-CSYM *)
               | MPatSym(_,ty4) -> 
                   let (ty2,e2') = typeof env e2 in               
                     if consistent (lift_type ty2) (lift_type ty3) then 
                       let (ty5,e2'',e3'') = lift_branch_cases e2' ty2 e3' ty3 in
                         (ty5, TmCase(fi,0,e1',p,e2'',e3''))
                     else raise (Mkl_type_error(TYPE_DECON_MISMATCH,ERROR,fi,[pprint_ty ty2; pprint_ty ty3])) 
                       (* L-CAPP *)
               | MPatSymApp(_,x1,x2) ->
                   let (ty2,e2') = typeof ((x1,ty_symdyn)::(x2,ty_symdyn)::env) e2 in               
                     if consistent (lift_type ty2) (lift_type ty3) then
                       let (ty4,e2'',e3'') = lift_branch_cases e2' ty2 e3' ty3 in 
                         (ty4, TmCase(fi,0,e1',p,e2'',e3''))
                     else raise (Mkl_type_error(TYPE_DECON_MISMATCH,ERROR,fi,[pprint_ty ty2; pprint_ty ty3]))
                       (* L-CLIFT *)
               | MPatLift(_,x,ty4) ->
                   let (ty2,e2') = typeof ((x,ty4)::env) e2 in               
                     if consistent (lift_type ty2) (lift_type ty3) then
                       let (ty5,e2'',e3'') = lift_branch_cases e2' ty2 e3' ty3 in
                         (ty5, TmCase(fi,0,e1',p,e2'',e3''))
                     else raise (Mkl_type_error(TYPE_DECON_MISMATCH,ERROR,fi,[pprint_ty ty2; pprint_ty ty3]))
            )            
          else
            raise (Mkl_type_error(TYPE_DECON_TYPE_NOT_MODEL,ERROR,fi,[pprint_ty ty1]))      
    | TmEqual(fi,_,e1,e2) ->
        let (ty1,e1') = typeof env e1 in
        let (ty2,e2') = typeof env e2 in
          if not (consistent (lift_type ty1) (lift_type ty2)) then
            raise (Mkl_type_error(TYPE_EQUAL_EXP_DIFF_TYPE,ERROR,fi,[pprint_ty ty1; pprint_ty ty2]))
          else
            let (ty3,e1'',e2'') = lift_branch_cases e1' ty1 e2' ty2 in
              (TyBool(NoInfo,0), TmEqual(fi,0,e1'',e2''))
    | TmLcase(fi,_,e1,x,xs,e2,e3)  ->
        let (ty1,e1') = typeof env e1 in
          if not (consistent ty1 (TyList(NoInfo,0,TyDyn(NoInfo,0)))) then
	    raise (Mkl_type_error(TYPE_LCASE_MATCHING_TM_NOT_LIST_TYPE,ERROR,tm_info e1,[pprint_ty ty1]))
          else
            let ty4 = match ty1 with TyList(_,_,ty) -> ty | ty -> ty in
            let (ty2,e2') = typeof ((xs,ty1)::(x,ty4)::env) e2 in
            let (ty3,e3') = typeof env e3 in
              if not (consistent (lift_type ty2) (lift_type ty3)) then
	        raise (Mkl_type_error(TYPE_LCASE_DIFFERENT_CASE_TYPES,ERROR,fi,[pprint_ty ty2; pprint_ty ty3]))
              else
                let (ty5,e2'',e3'') = lift_branch_cases e2' ty2 e3' ty3 in
                  (ty5, TmLcase(fi,0,e1',x,xs,e2'',e3''))
    | TmCons(fi,l,e1,e2) -> 
        let (ty1,e1') = typeof env e1 in
        let (ty2,e2') = typeof env e2 in
          if not (consistent ty2 (TyList(NoInfo,0,TyDyn(NoInfo,0)))) then
	    raise (Mkl_type_error(TYPE_CONS_TYPE_MISMATCH,ERROR,fi,[pprint_ty ty2]))
          else
            let ty3 = match ty2 with TyList(_,_,ty) -> ty | ty -> ty in
            if not (consistent ty1 ty3) then 
	      raise (Mkl_type_error(TYPE_CONS_TYPE_MISMATCH,ERROR,fi,[pprint_ty ty1;pprint_ty ty3]))
            else
              (meet (TyList(NoInfo,0,ty1)) ty2, TmCons(fi,0,e1',e2'))
    | TmNil(fi,l,ty)  ->  (TyList(fi,l,ty), TmNil(fi,l,ty))
    | TmTuple(fi,l,ts) -> 
	let (ty',ts') = ts |> List.map (typeof env) |> List.split in
	  (TyTuple(fi,l,ty'),TmTuple(fi,l,ts'))
    | TmProj(fi,_,i,e1) -> 
        let (ty1,e1') = typeof env e1 in
        (match ty1 with
           | TyTuple(_,_,tys) -> 
               if i < List.length tys 
               then (List.nth tys i, TmProj(fi,0,i,e1'))
               else raise (Mkl_type_error(TYPE_PROJ_TUPLE_SIZE,ERROR,fi,[ustring_of_int i; ustring_of_int (List.length tys)]))
           | TyDyn(_,_) | _ -> (TyDyn(NoInfo,0), TmProj(fi,0,i,e1')))
    | TmArray(fi,l,es) ->
	let (tys',es') = es |> Array.to_list |> List.map (typeof env) |> List.split in
        let checkelem aty ty =  
          if consistent aty ty then meet aty ty
          else raise (Mkl_type_error(TYPE_ARRAY_ELEM_NOT_CONSISTENT,ERROR, ty_info ty,[pprint_ty aty; pprint_ty ty]))
        in
        let tys' = List.fold_left checkelem (TyDyn(NoInfo,0)) tys' in
	  (TyArray(fi,l,tys'),TmArray(fi,l,Array.of_list es'))
    | TmArrayOp(fi,l,op,ts) ->
        let (ty',ts') = typeof_array_op fi l op ts env  in
          (ty',TmArrayOp(fi,l,op,ts'))
    | TmMapOp(fi,l,op,ts) -> 
        let (ty',ts') = typeof_map_op fi l op ts env  in
          (ty',TmMapOp(fi,l,op,ts'))
    | TmSetOp(fi,l,op,ts) -> 
        let (ty',ts') = typeof_set_op fi l op ts env  in
          (ty',TmSetOp(fi,l,op,ts'))
    | TmDAESolverOp(fi,l,op,ts) -> 
        let (ty',ts') = typeof_daesolver_op fi l op ts env  in
          (ty',TmDAESolverOp(fi,l,op,ts'))
    | TmDPrint(t) -> let (ty,t') = typeof env  t in (ty,TmDPrint(t'))
    | TmDPrintType(t) -> let (ty,t') = typeof env  t in (ty,TmDPrintType(t'))
    | TmError(fi,l,e1) ->
        let (ty1,e1') = typeof env e1 in
	(match ty1 with
	   | TyString(_,_)  -> (TyDyn(fi,0),TmError(fi,0,e1'))
	   | _ -> raise (Mkl_type_error(TYPE_ERROR_TERM_NOT_STRING,ERROR,ty_info ty1,[pprint_ty ty1])))
	  
          
let typeofterm t = fst (typeof [] t)

let typecheck t =
 (*  let _ = uprint_endline (pprint t) in *)
  snd (typeof [] t)

	 



