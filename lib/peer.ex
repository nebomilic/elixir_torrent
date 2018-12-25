defmodule Torrent.Peer do

  def connect(info_structs) do 
    { ip, port } = info_structs[:peer]

    { :ok, pid } = Task.start_link fn -> 
      Process.flag(:priority, :low)
      connect(ip, port) |> initiate_connection(info_structs)
    end
    pid
  end

  defp connect(ip, port, count \\ 0) do
    # IO.puts "Try to connect to: " <> ip
    try do
      Socket.TCP.connect!(ip, port, [timeout: 1000]) 
    rescue
      e ->
        if e.message == "timeout" do
          # IO.puts "got a Timeout on IP: " <> ip
          if count == 5 do
            # Torrent.Logger.log :peer, "fifth try on IP " <> ip <> " ... stopping now!"
            exit(:normal)
          else
            connect(ip, port, count + 1)
          end
        else
          exit(:normal)
        end
    end
  end

  def initiate_connection(socket, info_structs) do
    { info_hash, options } = socket 
      |> say_hello(info_structs[:meta_info]) 
      |> hear_hello

    verify_checksum info_hash, info_structs[:meta_info]
    # Torrent.Logger.log :peer, "handshake to peer completed"
    
    socket |> Torrent.Stream.leech(info_structs, options)
  end

  def verify_checksum(foreign_hash, meta_info) do
    real_hash = meta_info[:hash]
    if foreign_hash != real_hash do
      exit(:wrong_checksum)
    end
  end

  def say_hello(socket, meta_info) do
    handshake = generate_handshake meta_info[:hash]
    socket |> Socket.Stream.send!(handshake)
    socket
  end

  def hear_hello(socket) do 
    socket |> Socket.packet!(:raw)

    message = socket |> Torrent.Stream.recv_byte!(1)
    request_length = message |> :binary.bin_to_list |> Enum.at(0)

    answer = %{
      pstrlen: request_length,
      pstr: Torrent.Stream.recv_byte!(socket, request_length),
      placeholder: Torrent.Stream.recv_byte!(socket, 8),
      info_hash: Torrent.Stream.recv_byte!(socket, 20),
      peer_id: Torrent.Stream.recv_byte!(socket, 20)
    }
    { answer[:info_hash], Torrent.Parser.peer_extensions(answer[:placeholder]) }
  end

  defp generate_handshake(sha_info_hash) do
    # The Number 19 followed by the Protocol String
    << 19, "BitTorrent protocol" :: binary >> <>
    << 0, 0, 0, 0, 0, 20, 0, 0, sha_info_hash :: binary, >> <>
    # some Peer ID, also 20 Bytes long
    << generate_peer_id() :: binary >>
  end

  def generate_peer_id do
    # TODO: generate better Peer_id
    id = "BE"
    version = "0044"
    :rand.seed(:exs1024s, :erlang.timestamp)
    number = :rand.uniform(1000000000000)
    number = number |> Integer.to_string |> String.pad_leading(13, "0")
    "-#{id}#{version}#{number}"
  end

end
