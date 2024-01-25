import socket  # In ubuntu,lwip is not necessary
import struct
import time

c_pcb = None

DATA_LENGTH = 2048
SLEEP_TIME_SEC = 0.1
STATUS_ADDRESS = 0x40000008  # Replace with the actual address
SYNC_MASK = 0x00000001
Z_ENABLE_MASK = 0x00000002

# Encoder packet structure
tcp_data_format = "<HIIH"  # Format string for struct.pack/unpack

# Data buffer
intr_buf = []
intr_count = 0
test_counter = 0

# Synchronization packet handler
def push_intr_data(coarse, fine):
    intr_buf.append(struct.pack(tcp_data_format, 0x1207, coarse, fine, 0x570C))

def tcp_prt(pcb, prt_char):
    pcb.send(prt_char.encode('utf-8'))

# read the data from FIFO with transfer_data and send by TCP
def transfer_data(pcb):
    global intr_count, test_counter

    # Sleep
    time.sleep(SLEEP_TIME_SEC)

    # Replace the following with actual FIFO reading logic
    read_length = 10
    data = [struct.pack(tcp_data_format, 0x1207, i, i*2, 0xDA7A) for i in range(read_length)]

    # Send data to the client
    pcb.send(b"".join(data))

    test_counter += 1

    # Replace the following with actual synchronization logic
    ret_val = 1  # Replace with the actual value from hardware
    if ret_val & 0x00000001:
        print("\nPulse detected: ")
        push_intr_data(42, 84)  # Replace with actual synchronization data
        pcb.send(struct.pack(tcp_data_format, 0x1207, 42, 84, 0x570C))

    # Replace the following with actual UART data reading logic
    uart_count = 0
    while True:
         # Replace the following with actual UART reading logic
        uart_data = b"UART Data"
        if not uart_data:
            break
        pcb.send(struct.pack(tcp_data_format, 0x1207, uart_count, int.from_bytes(uart_data, 'big'), 0x2048))
        uart_count += 1

# recv_callback is a function called when receive the data from TCP client
def recv_callback(arg, pcb, p, err):
    global intr_buf

    # Do not read the packet if we are not in ESTABLISHED state
    if not p:
        pcb.close()
        return

    # Indicate that the packet has been received
    pcb.recv(p.len)

    data = p.raw
    for i in range(0, len(data), struct.calcsize(tcp_data_format)):
        # Replace the following with actual data processing logic
        header, coarse, fine, footer = struct.unpack_from(tcp_data_format, data, i)
        print("Received data:", header, coarse, fine, footer)

    # Free the received pbuf
    p.free()

# Close a TCP session
def tcp_rot_close(pcb):
    pcb.close()

# Error callback, TCP session aborted
def tcp_rot_err(arg, err):
    global c_pcb

    tcp_rot_close(c_pcb)
    c_pcb = None
    print("TCP connection aborted")

# accept_callback is a callback function called when new TCP connection is accepted
def accept_callback(arg, newpcb, err):
    global c_pcb
    if err == 0:
        print("Connection accepted")
    # Set the receive callback for this connection
        newpcb.recv(recv_callback)
        c_pcb = newpcb
        newpcb.err(tcp_rot_err)
    else:
        print(f"Error {err} while accepting connection")
    connection = 1
    # Just use an integer number indicating the connection id as the callback argument
    # newpcb.arg((void*)(UINTPTR)connection)

    # Increment for subsequent accepted connections
    # Replace the following with actual FIFO initialization logic
    print("Fifo initialization.")
    print(f"[ISR ]: {Xil_In32(0x40000000):08x}")
    Xil_Out32(0x40000000, 0xFFFFFFFF)
    print(f"[ISR ]: {Xil_In32(0x40000000):08x}")
    print(f"[IER ]: {Xil_In32(0x40000004):08x}")
    print(f"[RDFO]: {Xil_In32(0x4000001C):08x}")

    print("FIFO reset")
    Xil_Out32(0x40000018, 0x000000A5)
    while True:
        ret_val = Xil_In32(0x40000000)
        if ret_val & (1 << 23):
            Xil_Out32(0x40000000, (1 << 23) + (1 << 19))
            break
    print("FIFO reset fin.")

    return ERR_OK

def start_application():
    global c_pcb
    port = 8080

    # TCP protocol control block (PCB)
    pcb = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    pcb.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

    try:
        pcb.bind(('192.168.215.210', port))
    except Exception as e:
        print(f"Error binding to port {port}: {e}")
        return -2

    pcb.listen(1)
    print(f"TCP service started: port {port}")

    while True:
        try:
            client_sock, client_addr = pcb.accept()
            print(f"Accepted connection from {client_addr}")
            accept_callback(None, client_sock, 0)
        except Exception as e:
            print(f"Error accepting connection: {e}")
            break
    # Accept callback registration
    #pcb.accept(accept_callback)

    #print(f"TCP service started: port {port}")
    #return 0

# Entry point
if __name__ == "__main__":
    start_application()

    while True:
        try:
            if c_pcb:
                transfer_data(c_pcb)
            time.sleep(1)
        except KeyboardInterrupt:
            break
