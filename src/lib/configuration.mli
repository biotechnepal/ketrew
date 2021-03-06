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

(** Definition of the configuration (input to state creation; contents of the
    config-file). *)

open Ketrew_pure.Internal_pervasives
open Unix_io


(** {2 Construct Configuration Values} *)

type t
(** The contents of a configuration. *)

type plugin = [ `Compiled of string | `OCamlfind of string ]
(** The 2 kinds of dynamically loaded “plugins” accepted by Ketrew:

    - [`Compiled path]: path to a `.cma` or `.cmxs` compiled file.
    - [`OCamlfind package]: name of a Findlib package.

*)

type explorer_defaults
(** Configuration of the Explorer text-user-interface.  These
    configuration values can be changed at runtime within the explorer;
    but they are not persistent in that case. *)

val default_explorer_defaults : explorer_defaults
(** The default values of the Explorer configuration. *)

val explorer :
  ?request_targets_ids:[ `All | `Younger_than of [ `Days of float ] ] ->
  ?targets_per_page:int ->
  ?targets_to_prefetch:int -> unit -> explorer_defaults
(** Create a configuration of the Explorer:
    
    - [request_targets_ids]: is used to restrict how many targets are
      visible to the Explorer. 
       The default value is [`Younger_than (`Days 1.5)].
    - [targets_per_page]: how many targets to display in a given
      “page” (default [6]).
    - [targets_to_prefetch]: how many additional targets the Explorer
      should prefetch to speed-up navigation (default [6]).

 *)

type ui
(** General configuration of the text-based user interface. *)

val ui:
  ?with_color:bool ->
  ?explorer:explorer_defaults ->
  ?with_cbreak:bool ->
  unit -> ui
(** Create a configuration of the UI:
    
    - [with_color]: ask Ketrew to use ANSI colors (default: [true]).
    - [explorer]: the configuration of The Explorer (cf. {!explorer}).
    - [with_cbreak]: should the UI use “[cbreak]” or not.  When
      [false], it reads from [stdin] classically (i.e. it waits for
      the [return] key to be pressed); when [true], it gets the
      key-presses directly (it's the default but requires a compliant
      terminal).

 *)

type engine
(** The configuration of the engine, the component that orchestrates
    the run of the targets (used both for the server mode). *)

val engine: 
  ?turn_unix_ssh_failure_into_target_failure: bool ->
  ?host_timeout_upper_bound: float ->
  ?maximum_successive_attempts: int ->
  ?concurrent_automaton_steps: int ->
  ?engine_step_batch_size : int ->
  ?orphan_killing_wait : float ->
  database_parameters:string ->
  unit -> engine
(** Build an [engine] configuration:

    - [database_parameters]: the URI used to connect to the database
      (e.g. ["postgresql://example.com/db1"]).
    - [turn_unix_ssh_failure_into_target_failure]: when an
      SSH or system call fails it may not mean that the command in
      your workflow is wrong (could be an SSH configuration or
      tunneling problem). By default (i.e. [false]), Ketrew tries to
      be clever and does not make targets fail. To change this
      behavior set the option to [true].
    - [host_timeout_upper_bound]: every connection/command timeout
      will be “≤ upper-bound” (in seconds, default is [60.]).
    - [maximum_successive_attempts]: number of successive non-fatal
      failures allowed before declaring a target dead (default is [10]).
    - [concurrent_automaton_steps]: maximum number of steps in the
      state machine that engine will try to run concurrently (default
      is [4]).
    - [engine_step_batch_size]: the maximal amount of nodes that the engine
      will process in a single “step” (default: [400] nodes).
    - [orphan_killing_wait]: the minimal amount of time between 2
      attempts at killing all “orphan nodes” (i.e. unreachable because
      all dependees are finished).
*)

type authorized_tokens 
(** This type is a container for one more authentication-tokens,
    used by the server's HTTP API

    Tokens have a name and a value; the value is the one checked
    against the ["token"] argument of the HTTP queries.

    A token's value must consist only of
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_=".
 *)

val authorized_token: name: string -> string -> authorized_tokens
(** Create an “inline” authentication token, i.e. provide a [name] and
    a value directly. *)

val authorized_tokens_path: string -> authorized_tokens
  (** Ask the server to load tokens from a file at the given path.

      The file uses the SSH
      {{:http://en.wikibooks.org/wiki/OpenSSH/Client_Configuration_Files#.7E.2F.ssh.2Fauthorized_keys}[authorized_keys]} format.
      I.e. whitespace-separated lines of the form:
      {v
      <name> <token> <optional comments ...>
      v}
  *)

type server
(** The configuration of the server. *)

val server: 
  ?ui:ui ->
  ?authorized_tokens: authorized_tokens list ->
  ?return_error_messages: bool ->
  ?command_pipe: string ->
  ?log_path: string ->
  ?max_blocking_time: float ->
  ?read_only_mode: bool ->
  engine: engine ->
  [ `Tcp of int | `Tls of string * string * int ] ->
  [> `Server of server]
(** Create a server configuration (to pass as optional argument to the
    {!create} function).

    - [authorized_tokens]: cf. {!authorized_token} and
      {!authorized_tokens_path}.
    - [return_error_messages]: whether the server should return explicit error
      messages to clients (default [false]).
    - [command_pipe]: path to a named-piped for the server to listen to
      commands (this is optional but highly recommended).
    - [log_path]: path to the server's log directory; if present
      (highly recommended), the server will dump JSON files containing
      the logs periodically. Moreover, the server redirect debug-style
      logs to a ["debug.txt"] file in that directory (if not set,
      debug info goes to ["/dev/null"] or [stdout] if available).
    - [max_blocking_time]: 
      upper bound on the request for blocking in the protocol (seconds,
      default [300.]).
    - [read_only_mode]:
      run the server in read-only mode (default [false]).
    - [`Tcp port]: configure the server the unsercurely listen on [port].
    - [`Tls ("certificate.pem", "privatekey.pem", port)]: configure the OpenSSL
      server to listen on [port].
*)

type client
(** Configuration of the client (as in HTTP client). *)

val client: ?ui:ui -> token:string -> string -> [> `Client of client]
(** Create a client configuration:
    
    - [ui]: the configuration of the user-interface, cf. {!ui}.
    - [token]: the authentication token to use to connect to the
      server (the argument is optional but nothing interesting can
      happen without it).
    - the last argument is the connection URI,
      e.g. ["https://example.com:8443"].

*)

type mode = [
  | `Server of server
  | `Client of client
]
(** Union of the possible configuration “modes.” *)

val create :
  ?debug_level:int -> ?plugins: plugin list -> ?tmp_dir : string -> mode  -> t
(** Create a complete configuration:

    - [debug_level]: integer specifying the amount of verbosity
      (current useful values: [0] for quiet, [1] for verbose, [2] for
      extremely verbose —- [~debug_level:2] will slow down the engine
      noticeably).
    - [plugins]: cf. {!type:plugin}.
    - [mode]: cf. {!client}, and {!server}.
    - [tmp_dir]: Temporary directory to use (the default is
      [Filename.get_temp_dir_name ()]).

 *)

type profile
(** A profile is a name associated with a configuration. *)

val profile: string -> t -> profile
(** Create a profile value. *)

(** {2 Output/Serialize Configuration Profiles} *)

val output: profile list -> unit
(** Output a configuration file containing a list of profiles to [stdout]. *)

val to_json: profile list -> string
(** Create the contents of a configuration file containing a list of
    profiles. *)

(** {2 Access Configuration Values} *)

val default_configuration_directory_path: string
(** Default path to the configuration directory (["~/.ketrew/"]). *)

val database_parameters: engine -> string
(** Get the database parameters. *)

val is_unix_ssh_failure_fatal: engine -> bool
(** Should we kill targets on ssh/unix errors. *)

val maximum_successive_attempts: engine -> int
(** Get the maximum number of successive non-fatal failures. *)
  
val concurrent_automaton_steps: engine -> int
(** Get the maximum number of concurrent automaton steps. *)

val host_timeout_upper_bound : engine -> float option
(** Get the upper bound for the timeout of SSH calls, if any. *)

val engine_step_batch_size: engine -> int
(** Get the amount of workflow-nodes treated by the engine in one
    automaton step. *)

val orphan_killing_wait : engine -> float
(** Get the minimal time between 2 “orphan-node killing sprees.” *)

val plugins: t ->  plugin list
(** Get the configured list of plugins. *)

val mode: t -> mode

val server_engine: server -> engine

val server_configuration: t -> server option
(** Get the potentiel server configuration. *)

val authorized_tokens: server ->
  [ `Path of string | `Inline of (string * string)] list
(** The path to the [authorized_tokens] file. *)

val listen_to: server -> [ `Tcp of int | `Tls of string * string * int ]
(** Get the OpenSSL-or-not server configuration. *)

val return_error_messages: server -> bool
(** Get the value of [return_error_messages]. *)

val command_pipe: server -> string option
(** Get the path to the “command” named pipe. *)

val log_path: server -> string option
(** Get the path to the server's log directory. *)

val log: t -> Log.t
(** Get a display-friendly list of configuration items. *)

val connection: client -> string
val token: client -> string

val with_color: t -> bool
val request_targets_ids: t -> [ `All | `Younger_than of [ `Days of float ] ]
val targets_per_page: t -> int
val targets_to_prefetch: t -> int

val max_blocking_time: server -> float
val read_only_mode:    server -> bool

val use_cbreak: unit -> bool
(** See the documentation of [with_cbreak]. *)

val load_exn:
  ?and_apply:bool ->
  ?profile:string ->
  [ `From_path of string
  | `Guess
  | `In_directory of string
  | `Override of t ] ->
  t
(** Load a configuration.

    If [and_apply] is [true] (the default), then global settings are applied
    and plugins are loaded.

    When the configuration comes from a file, the argument [profile]
    allows to load a given profile. If [None] then the loading process
    will try the ["KETREW_PROFILE"] environment variable, or use the name
    ["default"].
    
    The last argument tells the functions how to load the configuration:
    
    - [`Override c]: use [c] as configuration
    - [`From_path path]: parse the file [path]
    - [`In_directory root]: look for configuration files in the [root]
      directory
    - [`Guess]: use environment variables and/or default values to
      find the configuration file.

   *)


