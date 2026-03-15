import socket
import sys
import time

def debug_vice(host="127.0.0.1", port=6502):
    print(f"Connecting to {host}:{port}...")
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(2.0)
    try:
        sock.connect((host, port))
        print("Connected! Waiting 1 second for any initial data...")
        time.sleep(1.0)
        
        sock.setblocking(False)
        try:
            data = sock.recv(1024)
            if data:
                print(f"Received {len(data)} bytes: {data.hex().upper()}")
                print(f"ASCII: {data.decode('ascii', errors='replace')}")
            else:
                print("Connected, but received 0 bytes (socket closed?).")
        except BlockingIOError:
            print("Connected, but no initial data sent by server.")
        
        # Try sending a PING (STX=02, API=02, Len=0, ID=1, Cmd=81)
        ping_packet = bytes.fromhex("0202000000000100000081")
        print(f"Sending PING: {ping_packet.hex().upper()}")
        sock.setblocking(True)
        sock.sendall(ping_packet)
        
        print("Waiting for response...")
        data = sock.recv(1024)
        print(f"Received response: {data.hex().upper()}")
        
    except Exception as e:
        print(f"Error: {e}")
    finally:
        sock.close()

if __name__ == "__main__":
    debug_vice()
