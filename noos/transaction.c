#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "lwip/err.h" //lwIPスタックに固有のヘッダー
#include "lwip/tcp.h"
#include "common/xil_printf.h" //Xilinxプラットフォームに固有のヘッダー
#include "common/xparameters.h"
#include "common/xil_io.h"
#include "common/xllfifo.h"
#include "common/xstatus.h"


#define DATA_LENGTH 2048
#define SLEEP_TIME_US 100000
#define STATUS_ADDRESS XPAR_AXI_GB_ROTARY_BASEADDR + 4
#define SYNC_MASK 0x00000001
#define Z_ENABLE_MASK 0x00000002

static struct tcp_pcb *c_pcb;
XLlFifo* FifoInstance;

// Encoder packet structure
#pragma pack(1)
typedef struct {
    u16 header;
    u32 stamp;
    u32 data;
    u16 footer;
} tcp_data;
#pragma pack()


// Data buffer
static tcp_data intr_buf[128];
static int intr_count = 0;
static int test_counter = 0;

// Synchronization packet handler
void push_intr_data(u32 coarse, u32 fine){
    int tmp_count = intr_count;
    intr_count++;
    intr_buf[tmp_count].header = 0x1207;
    intr_buf[tmp_count].stamp = coarse;
    intr_buf[tmp_count].data = fine;
    intr_buf[tmp_count].footer = 0x570C;
}

err_t tcp_prt(struct tcp_pcb *pcb, const char* prt_char){
    return tcp_write(pcb, prt_char, strlen(prt_char), 1);
}

// transfer_dataでFIFOからのデータを読み取り、処理してTCP経由で送信
err_t transfer_data() {
    u32 read_length;
    int i;
    int j = 0;
    tcp_data data[DATA_LENGTH];
    tcp_data sync;
    tcp_data uart;
    u32 ret_val;
    u64 ret_data;
    u32 tmp_len;
    u32 RxWord;
    u32 uart_count = 0;

    if (c_pcb == NULL) {
        return ERR_CONN;
    }

    // Sleep
    usleep(SLEEP_TIME_US);

    //XPAR_AXI_FIFO_0_BASEADDRRを使用して、FIFOからデータを読み取る
    while(1){ // Wait until at least one successful receive has completed
        ret_val = Xil_In32(XPAR_AXI_FIFO_0_BASEADDR + 0x00); // Interrupt Status Register
        if(ret_val & (1<<26)){ // Interrupt pending
            Xil_Out32(XPAR_AXI_FIFO_0_BASEADDR + 0x00, (1<<26) + (1<<19)); // RC clear & RFPE clear
            break;
        }
    }

    ret_val = Xil_In32(XPAR_AXI_FIFO_0_BASEADDR + 0x00);
    ret_val = Xil_In32(XPAR_AXI_FIFO_0_BASEADDR + 0x1C); // Receive Data FIFO Occupancy Register
    read_length = ret_val/2; // timestamp (coarse) & data (fine)

    for( i=0; i < read_length; i++ ){
        ret_val = Xil_In32(XPAR_AXI_FIFO_0_BASEADDR + 0x24); // Recieve Length Register
        if( ret_val != 8 ){ // Each AXIS packet has 32 bit (timestamp) + 32 bit (data) = 64 bit = 8 bytes length
            break;
        }
    //読み取ったデータをdata配列に格納している
        data[i].stamp = Xil_In32(XPAR_AXI_FIFO_0_BASEADDR + 0x20);
        data[i].data = Xil_In32(XPAR_AXI_FIFO_0_BASEADDR + 0x20);
        data[i].header = 0x1207;
        data[i].footer = 0xDA7A;
    }
    //ここでデータをSDカードに蓄える
    tcp_write(c_pcb, data, read_length*sizeof(*data), 1); //read_lengthは受信したデータの長さ

    test_counter++;

    ret_val = Xil_In32(XPAR_AXI_GB_ROTARY_BASEADDR + 4);
    if( ret_val & 0x00000001 ){
        xil_printf("\r\nPulse detected: ");
        Xil_Out32(XPAR_AXI_GB_ROTARY_BASEADDR + 4, ret_val & 0xFFFFFFFE);
        sync.header = 0x1207;
        sync.footer = 0x570C;
        sync.stamp = Xil_In32(XPAR_AXI_GB_ROTARY_BASEADDR + 8);
        sync.data = Xil_In32(XPAR_AXI_GB_ROTARY_BASEADDR + 12);
        tcp_write(c_pcb, &sync, sizeof(sync), 1); //tcp_write関数を使用して、クライアントにデータを送信
    }

    // uart
    while ( Xil_In32(XPAR_AXI_UARTLITE_BASEADDR + 8) & 0x00000001 ){ // Status register: RX FIFO valid data
        uart.header = 0x1207;
        uart.footer = 0x2048;
        uart.stamp = uart_count++;
        uart.data = Xil_In32(XPAR_AXI_UARTLITE_BASEADDR);
        tcp_write(c_pcb, &uart, sizeof(uart), 1);
    }

    return ERR_OK;
}

// recv_callbackでTCPクライアントからデータが受信されたときに呼び出される関数
err_t recv_callback(void *arg, struct tcp_pcb *tpcb,
                               struct pbuf *p, err_t err)
{
    u32 enc_val;
    u32 status;
    /* do not read the packet if we are not in ESTABLISHED state */
    if (!p) {
        tcp_close(tpcb);
        tcp_recv(tpcb, NULL);
        return ERR_OK;
    }

    /* indicate that the packet has been received */
    tcp_recved(tpcb, p->len);
    if (strcmp(p->payload, "e#reset_enable") == 0){
    	status = Xil_In32(STATUS_ADDRESS);
    	xil_printf("current status: %x\r\n", status);
    	Xil_Out32(STATUS_ADDRESS, status | Z_ENABLE_MASK);
    	status = Xil_In32(STATUS_ADDRESS);
    	xil_printf("current status: %x\r\n", status);
    } else if (strcmp(p->payload, "e#reset_disable") == 0) {
    	status = Xil_In32(STATUS_ADDRESS);
    	xil_printf("current status: %x\r\n", status);
    	Xil_Out32(STATUS_ADDRESS, status & (~Z_ENABLE_MASK));
    	status = Xil_In32(STATUS_ADDRESS);
    	xil_printf("current status: %x\r\n", status);;
    }


    if (tcp_sndbuf(tpcb) > p->len) {
        enc_val = Xil_In32(XPAR_AXI_GB_ROTARY_BASEADDR);
        xil_printf("%d\r\n", enc_val);
        err = tcp_write(tpcb, &enc_val, 4, 1);
    } else
        xil_printf("no space in tcp_sndbuf\n\r");

    /* free the received pbuf */
    pbuf_free(p);

    return ERR_OK;
}

/** Close a tcp session */
static void tcp_rot_close(struct tcp_pcb *pcb)
{
    err_t err;

    if (pcb != NULL) {
        tcp_recv(pcb, NULL);
        tcp_err(pcb, NULL);
        err = tcp_close(pcb);
        if (err != ERR_OK) {
            /* Free memory with abort */
            tcp_abort(pcb);
        }
    }
}

/** Error callback, tcp session aborted */
static void tcp_rot_err(void *arg, err_t err)
{
    LWIP_UNUSED_ARG(err);
    tcp_rot_close(c_pcb);
    c_pcb = NULL;
    xil_printf("TCP connection aborted\n\r");
}

// accept_callbackで新しいTCP接続が受け入れられたときに呼び出されるコールバック関数
err_t accept_callback(void *arg, struct tcp_pcb *newpcb, err_t err)
{
    static int connection = 1;
    u32 ret_val;

    /* set the receive callback for this connection */
    tcp_recv(newpcb, recv_callback);
    c_pcb = newpcb;
    tcp_err(c_pcb, tcp_rot_err);

    //err = tcp_prt(newpcb, "Hello, world!\r\n");
    connection++;
    /* just use an integer number indicating the connection id as the
       callback argument */

    //tcp_arg(newpcb, (void*)(UINTPTR)connection);

    /* increment for subsequent accepted connections */
    // FIFO initialization
    //tcp_prt(newpcb, "Going to initialize FIFO...\r\n");
    xil_printf("Fifo initialization.\r\n");
    ret_val = Xil_In32(XPAR_AXI_FIFO_0_BASEADDR + 0x00);
    xil_printf("[ISR ]: %08x\r\n", ret_val);
    Xil_Out32(XPAR_AXI_FIFO_0_BASEADDR + 0x00, 0xFFFFFFFF);
    ret_val = Xil_In32(XPAR_AXI_FIFO_0_BASEADDR + 0x00);
    xil_printf("[ISR ]: %08x\r\n", ret_val);
    ret_val = Xil_In32(XPAR_AXI_FIFO_0_BASEADDR + 0x04);
    xil_printf("[IER ]: %08x\r\n", ret_val);
    ret_val = Xil_In32(XPAR_AXI_FIFO_0_BASEADDR + 0x1C);
    xil_printf("[RDFO]: %08x\r\n", ret_val);


    xil_printf("FIFO reset\r\n");
    Xil_Out32(XPAR_AXI_FIFO_0_BASEADDR + 0x18, 0x000000A5);
    while(1){
        ret_val = Xil_In32(XPAR_AXI_FIFO_0_BASEADDR + 0x00);
        if(ret_val & (1<<23)){
            Xil_Out32(XPAR_AXI_FIFO_0_BASEADDR + 0x00, (1<<23) + (1<<19));
            break;
        }
    }
    xil_printf("FIFO reset fin.\r\n");
    //tcp_prt(newpcb, "FIFO reset fin.\r\n");

    return ERR_OK;
}


int start_application()
{
    struct tcp_pcb *pcb;
    err_t err;
    unsigned port = 7;

    // TCP protocol control block (PCB)
    pcb = tcp_new_ip_type(IPADDR_TYPE_ANY);
    if (!pcb) {
        xil_printf("tcp_new_ip_type error. quit. \n\r");
        return -1;
    }

    // TCP bind (port configuration)
    err = tcp_bind(pcb, IP_ANY_TYPE, port);
    if (err != ERR_OK) {
        xil_printf("Error on tcp_bind to port %d: err = %d\n\r", port, err);
        return -2;
    }

    tcp_arg(pcb, NULL);

    // TCP listen
    pcb = tcp_listen(pcb);
    if (!pcb) {
        xil_printf("Out of memory while tcp_listen\n\r");
        return -3;
    }

    // LISTEN callback registration
    tcp_accept(pcb, accept_callback);

    xil_printf("TCP service started: port %d\n\r", port);
    return 0;
}
