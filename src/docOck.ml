(*
 * Copyright (c) 2014 Leo White <lpw25@cl.cam.ac.uk>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

module Paths = DocOckPaths

module Types = DocOckTypes

let core_types = DocOckPredef.core_types

let core_exceptions = DocOckPredef.core_exceptions

type 'a result =
  | Ok of 'a Types.Unit.t
  | Not_an_interface
  | Wrong_version
  | Corrupted
  | Not_a_typedtree
  | Not_an_implementation

let read_cmti root_fn filename =
  let open Cmi_format in
  let open Cmt_format in
  let open Types.Unit in
  try
    let cmt_info = read_cmt filename in
    match cmt_info.cmt_annots with
    | Interface intf -> begin
      match cmt_info.cmt_interface_digest with
      | Some digest ->
        let name = cmt_info.cmt_modname in
        let root = root_fn name digest in
        let (id, doc, items) = DocOckCmti.read_interface root name intf in
        let imports =
          List.filter (fun (name', _) -> name <> name') cmt_info.cmt_imports
        in
        let imports =
          List.map (fun (s, d) -> Import.Unresolved(s, d)) imports
        in
        let interface = true in
        let source =
          match cmt_info.cmt_sourcefile, cmt_info.cmt_source_digest with
          | Some file, Some digest ->
            let open Source in
            let build_dir = cmt_info.cmt_builddir in
            Some {file; digest; build_dir}
          | _, _ -> None
        in
        let content = Module items in
        let unit =
          {id; doc; digest; imports;
           source; interface; content}
        in
        let unit = DocOckLookup.lookup unit in
          Ok unit
      | None -> Corrupted
    end
    | _ -> Not_an_interface
  with
  | Cmi_format.Error (Not_an_interface _) -> Not_an_interface
  | Cmi_format.Error (Wrong_version_interface _) -> Wrong_version
  | Cmi_format.Error (Corrupted_interface _) -> Corrupted
  | Cmt_format.Error (Not_a_typedtree _) -> Not_a_typedtree

let read_cmt root_fn filename =
  let open Cmi_format in
  let open Cmt_format in
  let open Types.Unit in
  try
    let cmt_info = read_cmt filename in
    match cmt_info.cmt_annots with
    | Packed(sg, files) ->
        let name = cmt_info.cmt_modname in
        let interface, digest =
          match cmt_info.cmt_interface_digest with
          | Some digest -> true, digest
          | None ->
            match List.assoc name cmt_info.cmt_imports with
            | Some digest -> false, digest
            | None -> assert false
            | exception Not_found -> assert false
        in
        let root = root_fn name digest in
        let id = DocOckPaths.Identifier.Root(root, name) in
        let items =
          List.map
            (fun file ->
               let pref = Misc.chop_extensions file in
                 String.capitalize(Filename.basename pref))
            files
        in
        let items =
          List.map
            (fun name ->
               let open Packed in
               let id = Paths.Identifier.Root(root, name) in
               let path = Paths.Path.Root name in
                 {id; path})
            items
        in
        let imports =
          List.filter (fun (name', _) -> name <> name') cmt_info.cmt_imports
        in
        let imports =
          List.map (fun (s, d) -> Import.Unresolved(s, d)) imports
        in
        let doc = DocOckAttrs.empty in
        let source = None in
        let content = Pack items in
          Ok {id; doc; digest; imports; source; interface; content}
    | Implementation impl ->
        let open Types.Unit in
        let name = cmt_info.cmt_modname in
        let interface, digest =
          match cmt_info.cmt_interface_digest with
          | Some digest -> true, digest
          | None ->
              match List.assoc name cmt_info.cmt_imports with
              | Some digest -> false, digest
              | None -> assert false
              | exception Not_found -> assert false
        in
        let root = root_fn name digest in
        let (id, doc, items) = DocOckCmt.read_implementation root name impl in
        let imports =
          List.filter (fun (name', _) -> name <> name') cmt_info.cmt_imports
        in
        let imports =
          List.map (fun (s, d) -> Import.Unresolved(s, d)) imports
        in
        let source =
          match cmt_info.cmt_sourcefile, cmt_info.cmt_source_digest with
          | Some file, Some digest ->
            let open Source in
            let build_dir = cmt_info.cmt_builddir in
            Some {file; digest; build_dir}
          | _, _ -> None
        in
        let content = Module items in
        let unit =
          {id; doc; digest; imports;
           source; interface; content}
        in
        let unit = DocOckLookup.lookup unit in
          Ok unit
    | _ -> Not_an_implementation
  with
  | Cmi_format.Error (Not_an_interface _) -> Not_an_implementation
  | Cmi_format.Error (Wrong_version_interface _) -> Wrong_version
  | Cmi_format.Error (Corrupted_interface _) -> Corrupted
  | Cmt_format.Error (Not_a_typedtree _) -> Not_a_typedtree

let read_cmi root_fn filename =
  let open Cmi_format in
  let open Types.Unit in
  try
    let cmi_info = read_cmi filename in
      match cmi_info.cmi_crcs with
      | (name, Some digest) :: imports when name = cmi_info.cmi_name ->
          let root = root_fn name digest in
          let (id, doc, items) =
            DocOckCmi.read_interface root name cmi_info.cmi_sign
          in
          let imports =
            List.map (fun (s, d) -> Import.Unresolved(s, d)) imports
          in
          let interface = true in
          let source = None in
          let content = Module items in
          let unit =
            {id; doc; digest; imports;
             source; interface; content}
          in
          let unit = DocOckLookup.lookup unit in
            Ok unit
      | _ -> Corrupted
  with
  | Cmi_format.Error (Not_an_interface _) -> Not_an_interface
  | Cmi_format.Error (Wrong_version_interface _) -> Wrong_version
  | Cmi_format.Error (Corrupted_interface _) -> Corrupted

type 'a resolver = 'a DocOckResolve.resolver

let build_resolver = DocOckResolve.build_resolver

let resolve = DocOckResolve.resolve

type 'a expander = unit

let build_expander fetch = ()

type 'a expansion =
  | Signature of 'a Types.Signature.t
  | Functor of ('a Paths.Identifier.module_ *
                'a Types.ModuleType.expr) option list *
               'a Types.Signature.t

let rec expand_module_type () = function
  | Types.ModuleType.Path _ -> None
  | Types.ModuleType.Signature sg -> Some (Signature sg)
  | Types.ModuleType.Functor(arg, expr) -> begin
      match expand_module_type () expr with
      | None -> None
      | Some (Signature sg) -> Some(Functor([arg], sg))
      | Some (Functor(args, sg)) -> Some(Functor(arg :: args, sg))
    end
  | Types.ModuleType.With _ -> None
  | Types.ModuleType.TypeOf decl -> expand_module () decl

and expand_module () = function
  | Types.Module.Alias _ -> None
  | Types.Module.ModuleType expr -> expand_module_type () expr
