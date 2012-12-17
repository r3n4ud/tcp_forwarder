#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'celluloid/io'

# BUFFER_SIZE must be > 1448
BUFFER_SIZE = 8192

class TcpProxy
  include Celluloid::IO

  def initialize(host, port, dest_host, dest_port)
    @server = TCPServer.new(host, port)
    @dest_host = dest_host
    @dest_port = dest_port
    run!
  end

  def run
    loop do
      handle_connection! @server.accept
    end
  end

  # def forward(s)
  #   socket = TCPSocket.new(@dest_host, @dest_port)
  #   socket.write(s)
  #   # StringIO here to store the whole response
  #   r = socket.read(BUFFER_SIZE)
  #   socket.close
  #   r
  # end

  def handle_connection(socket)
    _, port, host = socket.peeraddr
    puts "*** Received connection from #{host}:#{port}"

    puts '*** Read request'
    request_data = StringIO.new
    chunked = false
    request_eof = false

    until request_eof do
      data = socket.readpartial(BUFFER_SIZE)
      request_data << data

      chunked = true if data =~ /Transfer-Encoding: chunked/
      if chunked
        request_eof = true if data =~ /\r\n0\r\n/
      else
        request_eof = !(data.bytesize == BUFFER_SIZE)
      end

    end

    puts '*** Forward request'
    puts request_data.string
    request_data.rewind

    client = TCPSocket.new(@dest_host, @dest_port)
    request_eof = false
    until request_eof do
      client.write request_data.read(BUFFER_SIZE)
      request_eof = request_data.eof
    end

    puts '*** Read response'
    response_data = StringIO.new
    chunked = false
    response_eof = false

    until response_eof do
      data = client.readpartial(BUFFER_SIZE)
      response_data << data

      chunked = true if data =~ /Transfer-Encoding: chunked/

      if chunked
        response_eof = true if data =~ /\r\n0\r\n/
      else
        response_eof = !(data.bytesize == BUFFER_SIZE || data.bytesize == 1448)
      end

    end

    puts '*** Forward response'
    puts response_data.string
    response_data.rewind

    response_eof = false
    until response_eof do
      socket.write response_data.read(BUFFER_SIZE)
      response_eof = response_data.eof
    end

    # We are done with both sockets
    client.close
    socket.close
  rescue EOFError
    puts "*** #{host}:#{port} disconnected"
  end
end

supervisor = TcpProxy.supervise('127.0.0.1', 10000, '127.0.0.1', 3000)
trap("INT") { supervisor.terminate; exit }
sleep
