
(**
Convenient wrapper around [React] and [ReactiveData] modules.
*)

type 'a signal = 'a React.S.t

type 'a signal_list_wrap = 'a ReactiveData.RList.t

module Source: sig
  type 'a t
  val create: ?eq:('a -> 'a -> bool) -> 'a -> 'a t
  val set: 'a t -> 'a -> unit
  val signal: 'a t -> 'a signal
  val value: 'a t -> 'a
  val modify: 'a t -> f:('a -> 'a) -> unit
  val modify_opt: 'a t -> f:('a -> 'a option) -> unit
  val map_signal: 'a t -> f:('a -> 'b) -> 'b signal

end
module Signal: sig
  type 'a t = 'a signal
  val map: 'a t -> f:('a -> 'b) -> 'b t
  val bind: 'a t -> f:('a -> 'b t) -> 'b t
  val constant: 'a -> 'a t
  val value: 'a t -> 'a
  val singleton: 'a t -> 'a signal_list_wrap
  val list: 'a list t -> 'a signal_list_wrap
  val tuple_2: 'a t -> 'b t -> ('a * 'b) t
  val tuple_3: 'a t -> 'b t -> 'c t -> ('a * 'b * 'c) t
end
