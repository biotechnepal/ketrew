(**************************************************************************)
(*    Copyright 2014, 2015:                                               *)
(*          Sebastien Mondet <seb@mondet.org>,                            *)
(*          Leonid Rozenberg <leonidr@gmail.com>,                         *)
(*          Arun Ahuja <aahuja11@gmail.com>,                              *)
(*          Jeff Hammerbacher <jeff.hammerbacher@gmail.com>               *)
(*                                                                        *)
(*  Licensed under the Apache License, Version 2.0 (the "License");       *)
(*  you may not use this file except in compliance with the License.      *)
(*  You may obtain a copy of the License at                               *)
(*                                                                        *)
(*      http://www.apache.org/licenses/LICENSE-2.0                        *)
(*                                                                        *)
(*  Unless required by applicable law or agreed to in writing, software   *)
(*  distributed under the License is distributed on an "AS IS" BASIS,     *)
(*  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or       *)
(*  implied.  See the License for the specific language governing         *)
(*  permissions and limitations under the License.                        *)
(**************************************************************************)

open Ketrew_pure
open Internal_pervasives
open Unix_io


type plugin = [ `Compiled of string | `OCamlfind of string ]
              [@@deriving yojson]

let default_engine_step_batch_size = 400

let default_orphan_killing_wait = 600. (* 10 minutes *)

type engine = {
  database_parameters: string;
  turn_unix_ssh_failure_into_target_failure: (bool [@default false]);
  host_timeout_upper_bound: (float option [@default None]);
  maximum_successive_attempts: (int [@default 10]);
  concurrent_automaton_steps: (int [@default 4]);
  engine_step_batch_size: (int [@default default_engine_step_batch_size]);
  orphan_killing_wait: (float [@default default_orphan_killing_wait])
} [@@deriving yojson]
type explorer_defaults = {
  request_targets_ids: [ `All | `Younger_than of [ `Days of float ]];
  targets_per_page: int;
  targets_to_prefetch: int;
} [@@deriving yojson]
type ui = {
  with_color: bool;
  explorer: explorer_defaults;
  with_cbreak: bool;
} [@@deriving yojson]
type authorized_tokens = [
  | `Path of string
  | `Inline of string * string
] [@@deriving yojson]
type server = {
  authorized_tokens: authorized_tokens list;
  listen_to: [
    | `Tls of (string * string * int)
    | `Tcp of int
  ];
  return_error_messages: bool;
  command_pipe: string option;
  log_path: string option;
  server_engine: engine;
  server_ui: ui;
  max_blocking_time: (float [@default 300.]);
  read_only_mode: (bool [@default false]);
} [@@deriving yojson]
type client = {
  connection: string;
  token: string;
  client_ui : ui [@key "ui"];
} [@@deriving yojson]
type mode = [
  | `Client of client
  | `Server of server
] [@@deriving yojson]

type t = {
  debug_level: int;
  plugins: (plugin list [@default []]);
  mode: mode;
  tmp_dir: (string option [@default None]);
} [@@deriving yojson]

let log t =
  let open Log in
  let item name l = s name % s ": " % l in
  let toplevel l = separate n l in
  let sublist l = n % indent (separate n l) in
  let common =
    sublist [
      item "Debug-level" (i t.debug_level);
      item "Plugins" (match t.plugins with
        | [] -> s "None"
        | more -> sublist (List.map more ~f:(function
          | `Compiled path -> item "Compiled"  (quote path)
          | `OCamlfind pack -> item "OCamlfind package" (quote pack))));
      item "Tmp-dir"
        (match t.tmp_dir with
        | None -> sf "Not-specified (using %s)" Filename.(get_temp_dir_name ())
        | Some p -> sf "Set: %s" p);
    ] in
  let ui t =
    sublist [
      item "Colors"
        (if t.with_color then s "with colors" else s "without colors");
      item "Get-key"
        (if t.with_cbreak then s "uses `cbreak`" else s "classic readline");
      item "Explorer"
        (let { request_targets_ids; targets_per_page; targets_to_prefetch } =
           t.explorer in
         sublist [
           item "Default request"
             (match request_targets_ids with
             | `Younger_than (`Days days) ->
               s "Targets younger than " % f days % s " days"
             | `All -> s "All targets");
           item "Targets-per-page" (i targets_per_page);
           item "Targets-to-prefectch" (i targets_to_prefetch);
         ]);
    ] in
  let engine { database_parameters; turn_unix_ssh_failure_into_target_failure;
               host_timeout_upper_bound; maximum_successive_attempts;
               concurrent_automaton_steps;
               engine_step_batch_size; orphan_killing_wait} =
    sublist [
      item "Database" (quote database_parameters);
      item "Unix-failure"
        ((if turn_unix_ssh_failure_into_target_failure
          then s "turns"
          else s "does not turn") % s " into target failure");
      item "Host-timeout-upper-bound"
        (option f host_timeout_upper_bound);
      item "Maximum-successive-attempts" (i maximum_successive_attempts);
      item "Concurrent-automaton-steps" (i concurrent_automaton_steps);
      item "Engine-step-batch-size" (i engine_step_batch_size);
      item "Orphan-node-wait" (f orphan_killing_wait);
    ] in
  let authorized_tokens = function
  | `Path path -> s "Path: " % quote path
  | `Inline (name, value) ->
    s "Inline " % parens (s "Name: " % s name % s ", Value: " % quote value)
  in
  match t.mode with
  | `Client client ->
    toplevel [
      item "Mode" (s "Client");
      item "Connection" (quote client.connection);
      item "Auth-token" (quote client.token);
      item "UI" (ui client.client_ui);
      item "Misc" common;
    ]
  | `Server srv ->
    toplevel [
      item "Mode" (s "Server");
      item "Engine" (engine srv.server_engine);
      item "UI" (ui srv.server_ui);
      item "HTTP-server" (sublist [
          item "Authorized tokens"
            (sublist (List.map ~f:authorized_tokens srv.authorized_tokens));
          item "Command Pipe" (OCaml.option quote srv.command_pipe);
          item "Log-path" (OCaml.option quote srv.log_path);
          item "Return-error-messages" (OCaml.bool srv.return_error_messages);
          item "Max-blocking-time" (OCaml.float srv.max_blocking_time);
          item "Listen"
            begin match srv.listen_to with
            | `Tls (cert, key, port) ->
              item "HTTPS" (
                sublist [
                  item "Port" (i port);
                  item "Certificate" (quote cert);
                  item "Key" (quote key);
                ])
            | `Tcp port -> item "HTTP" (i port)
            end
        ]);
      item "Misc" common;
    ]


let default_configuration_directory_path =
  Sys.getenv "HOME" ^ "/.ketrew/"
  

let create ?(debug_level=0) ?(plugins=[]) ?tmp_dir mode =
  {debug_level; plugins; mode; tmp_dir}


let explorer
  ?(request_targets_ids = `Younger_than (`Days 1.5))
  ?(targets_per_page = 6)
  ?(targets_to_prefetch = 6) () =
  {request_targets_ids; targets_to_prefetch; targets_per_page }

let default_explorer_defaults : explorer_defaults = explorer ()

let ui
    ?(with_color=true)
    ?(explorer=default_explorer_defaults)
    ?(with_cbreak=true) () =
  {with_color; explorer; with_cbreak}
let default_ui = ui ()

let engine
    ?(turn_unix_ssh_failure_into_target_failure=false)
    ?host_timeout_upper_bound
    ?(maximum_successive_attempts=10)
    ?(concurrent_automaton_steps = 4)
    ?(engine_step_batch_size = default_engine_step_batch_size)
    ?(orphan_killing_wait = default_orphan_killing_wait)
    ~database_parameters
    () = {
  database_parameters;
  turn_unix_ssh_failure_into_target_failure;
  host_timeout_upper_bound;
  maximum_successive_attempts;
  concurrent_automaton_steps;
  engine_step_batch_size;
  orphan_killing_wait;
}

let client ?(ui=default_ui) ~token connection =
  (`Client {client_ui = ui; connection; token})

let authorized_token ~name value = `Inline (name, value)
let authorized_tokens_path p = `Path p

let server
    ?ui
    ?(authorized_tokens=[]) ?(return_error_messages=false)
    ?command_pipe ?log_path
    ?(max_blocking_time = 300.)
    ?(read_only_mode = false)
    ~engine
    listen_to =
  let server_ui = Option.value ui ~default:default_ui in
  (`Server {server_engine = engine; authorized_tokens; listen_to; server_ui;
            return_error_messages; command_pipe; log_path;
            max_blocking_time; read_only_mode;})


let plugins t = t.plugins

let server_configuration t =
  match t.mode with
  | `Server s -> Some s
  | other -> None
let listen_to s = s.listen_to
let return_error_messages s = s.return_error_messages
let authorized_tokens s = s.authorized_tokens
let command_pipe s = s.command_pipe
let log_path     s = s.log_path
let database_parameters e = e.database_parameters
let engine_step_batch_size e = e.engine_step_batch_size
let orphan_killing_wait e = e.orphan_killing_wait
let is_unix_ssh_failure_fatal e = e.turn_unix_ssh_failure_into_target_failure
let maximum_successive_attempts e = e.maximum_successive_attempts
let concurrent_automaton_steps e = e.concurrent_automaton_steps
let host_timeout_upper_bound e = e.host_timeout_upper_bound
let mode t = t.mode
let server_engine s = s.server_engine
let connection c = c.connection
let token c = c.token
let max_blocking_time s = s.max_blocking_time
let read_only_mode s = s.read_only_mode

let get_ui (t: t) =
  match t.mode with
  | `Server { server_ui; _ } -> server_ui
  | `Client { client_ui; _ } -> client_ui

let with_color t = get_ui t |> fun ui -> ui.with_color
let request_targets_ids t = get_ui t |> fun ui -> ui.explorer.request_targets_ids
let targets_per_page t = get_ui t |> fun ui -> ui.explorer.targets_per_page
let targets_to_prefetch t = get_ui t |> fun ui -> ui.explorer.targets_to_prefetch

module File = struct
  type configuration = t
   [@@deriving yojson]
  type profile = {
    name: string;
    configuration: configuration;
  } [@@deriving yojson]
  type t = [
    | `Ketrew_configuration of profile list [@name "Ketrew"]
  ] [@@deriving yojson]

  let parse_string_exn s =
    let open Ppx_deriving_yojson_runtime.Result in
    match Yojson.Safe.from_string s |> of_yojson with
    | Ok o -> o
    | Error e -> failwith (fmt "Configuration parsing error: %s" e)

  let to_string s = to_yojson s |> Yojson.Safe.pretty_to_string ~std:true

  let get_profile t the_name =
    match t with
    | `Ketrew_configuration profiles ->
      List.find_map profiles ~f:(fun {name; configuration} ->
          if name = the_name then Some configuration else None)

  let pick_profile_exn ?name t =
    let name =
      match name with
      | Some n -> n
      | None ->
        try Sys.getenv "KETREW_PROFILE" with
        | _ -> "default"
    in
    get_profile t name
    |> Option.value_exn ~msg:(fmt "profile %S not found" name)

  let default_ketrew_path =
    default_configuration_directory_path

  let default_configuration_filenames = [
    "configuration.json";
    "configuration.ml";
    "configuration.sh";
    "configuration.url";
  ]

  let get_path ?root () =
    let env n () = try Some (Sys.getenv n) with | _ -> None in
    let try_options l ~and_then =
      match List.find_map l ~f:(fun f -> f ()) with
      | Some s -> s
      | None -> and_then () in
    let findout_path () =
      try_options [
        (fun () -> root);
        env "KETREW_ROOT";
      ]
        ~and_then:(fun () -> default_ketrew_path) in
    let find_in_path ketrew_path =
      try_options
        (List.map default_configuration_filenames
           ~f:(fun name ->
               fun () ->
                 let path = Filename.concat ketrew_path name in
                 if Sys.file_exists path then Some path else None))
        ~and_then:(fun () -> Filename.concat ketrew_path "configuration.json")
    in
    try_options [
      env "KETREW_CONFIGURATION";
      env "KETREW_CONFIG";
    ]
      ~and_then:(fun () ->
          let ketrew_path = findout_path () in
          find_in_path ketrew_path)

  let read_file_no_lwt path =
    let i = open_in path in
    let content =
      let buf = Buffer.create 1023 in
      let rec get_all () =
        begin try
          let line = input_line i in
          Buffer.add_string buf (line ^ "\n");
          get_all ()
        with e -> ()
        end;
      in
      get_all ();
      Buffer.contents buf in
    close_in i;
    content

  let read_command_output_no_lwt_exn cmd =
    let ic = Unix.open_process_in cmd in
    let buf = Buffer.create 24 in
    begin try
      while true do
        Buffer.add_char buf (input_char ic)
      done
    with End_of_file -> ()
    end;
    begin match Unix.close_process_in ic with
    | Unix.WEXITED 0 -> Buffer.contents buf
    | _ -> failwith (fmt "failed command: %S" cmd)
    end


  let load_exn path =
    let split = String.split ~on:(`Character '.') path in
    let extension =
      match split with
      | [] | [_] -> None
      | more -> List.last more in
    match extension with
    | Some "json" ->
      read_file_no_lwt path |> parse_string_exn
    | Some "ml" ->
      read_command_output_no_lwt_exn
        (fmt "ocaml %s" Filename.(quote path))
      |> parse_string_exn
    | Some "sh" ->
      read_command_output_no_lwt_exn path
      |> parse_string_exn
    | Some "url" ->
      failwith "Getting config from URL: not implemented"
    | None | Some _ ->
      Log.(s "The Config-file should have a discriminatory extension \
              (.ml, .sh, or .json); the file " % quote path
           % s " has "
           % Option.value_map ~default:(s "no extension") extension 
             ~f:(fun ext -> s "extension " % quote ext) 
           % s ", Ketrew will continue assuming the format is JSON."
           @ warning);
      read_file_no_lwt path |> parse_string_exn

end

let using_cbreak = ref true
let use_cbreak () =
  !using_cbreak
let set_using_cbreak from_config =
  using_cbreak :=
    (try
      match Sys.getenv "WITH_CBREAK" with
      | "no" | "false" -> false
      | "yes" | "true" -> true
      | other -> from_config
    with _ -> from_config)

let apply_globals t =
  global_debug_level := t.debug_level;
  begin match t.tmp_dir with
  | None -> ()
  | Some path ->
    Sys.command (fmt "mkdir -p %s" (Filename.quote path)) |> ignore;
    Filename.set_temp_dir_name path;
  end;
  let color, host_timeout, cbreak =
    match t.mode with
    | `Client {client_ui; connection; token} ->
      (client_ui.with_color, None, client_ui.with_cbreak)
    | `Server {server_engine; server_ui; _} ->
      (server_ui.with_color, server_engine.host_timeout_upper_bound,
       server_ui.with_cbreak)
  in
  global_with_color := color;
  set_using_cbreak cbreak;
  Log.(s "Configuration: setting globals: "
       % indent (n
         % s "debug_level: " % i !global_debug_level % n
         % s "with_color: " % OCaml.bool !global_with_color % n
         % s "timeout upper bound: " % OCaml.(option float host_timeout) % n
         % s "tmp_dir: " % OCaml.(option quote t.tmp_dir)
       ) @ very_verbose);
  begin match host_timeout with
  | Some ht -> Host_io.default_timeout_upper_bound := ht
  | None -> ()
  end

let load_exn ?(and_apply=true) ?profile how =
  let potential_error_log = ref [] in
  let add_log l = potential_error_log := l :: !potential_error_log in
  add_log Log.(s "Configuration profile: "
               % s (Option.value profile ~default:"default"));
  begin try
    let conf =
      let open File in
      match how with
      | `Override c -> c
      | `From_path path ->
        add_log
          Log.(s "Configuration path provided manually: " % quote path);
        (load_exn path |> pick_profile_exn ?name:profile)
      | `In_directory root ->
        let path = get_path ~root () in
        add_log
          Log.(s "Configuration path guessed from directory " % quote root
               % parens (s "provided manually ") % s ": " % quote path);
        (load_exn path |> pick_profile_exn ?name:profile)
      | `Guess ->
        let path = get_path () in
        add_log
          Log.(s "Configuration path guessed from environment/defaults: "
               % quote path);
        (load_exn path |> pick_profile_exn ?name:profile)
    in
    if and_apply then (
      apply_globals conf;
      add_log Log.(s "Plugins to load: " % i (List.length conf.plugins));
      Plugin.load_plugins_no_lwt_exn conf.plugins
    );
    conf
  with e ->
    Log.(
      let environment_variables =
        let all_environment_variables = [
          "KETREW_ROOT";
          "KETREW_CONFIGURATION";
          "KETREW_CONFIG";
          "KETREW_PROFILE";
        ] in
        List.map all_environment_variables ~f:(fun name ->
            s name % s ": "
            % (try quote (Sys.getenv name) with _ -> s "Not defined")) in
      s "Loading of the configuration failed: " % n
         % s "Exception: " % exn e % n
         % s "Details: " % n % indent (separate n !potential_error_log) % n
         % s "Environment: " % n
         % indent (separate n environment_variables) % n
         % s "See also: http://www.hammerlab.org/docs/ketrew/master/\
              The_Configuration_File.html" % n
         @ error);
    raise e
  end


type profile = File.profile

let profile name configuration =
  File.({name; configuration})

let output l =
  File.(`Ketrew_configuration l |> to_string |> print_string)

let to_json l =
  File.(`Ketrew_configuration l |> to_string)
