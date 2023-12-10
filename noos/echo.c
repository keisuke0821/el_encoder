/******************************************************************************
*
* Copyright (C) 2009 - 2014 Xilinx, Inc.  All rights reserved.
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in
* all copies or substantial portions of the Software.
*
* Use of the Software is limited solely to applications:
* (a) running on a Xilinx device, or
* (b) that interact with a Xilinx device through a bus or interconnect.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
* XILINX  BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
* WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF
* OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
*
* Except as contained in this notice, the name of the Xilinx shall not be used
* in advertising or otherwise to promote the sale, use or other dealings in
* this Software without prior written authorization from Xilinx.
*
******************************************************************************/

#include <stdio.h>
#include <string.h>
#include "sleep.h"

#include "lwip/err.h"
#include "lwip/tcp.h"
#if defined (__arm__) || defined (__aarch64__)
#include "xil_printf.h"
#include "xparameters.h"
#include "xil_io.h"
#include "xllfifo.h"
#include "xstatus.h"
#endif

#define DATA_LENGTH 2048
#define SLEEP_TIME_US 100000

static struct tcp_pcb *c_pcb;
XLlFifo* FifoInstance;

#pragma pack(1)
typedef struct {
    u16 header;
    u32 stamp;
    u32 data;
    u16 footer;
} tcp_data;
#pragma pack()


static tcp_data intr_buf[128];
static int intr_count = 0;
static int test_counter = 0;

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

        data[i].stamp = Xil_In32(XPAR_AXI_FIFO_0_BASEADDR + 0x20);
        data[i].data = Xil_In32(XPAR_AXI_FIFO_0_BASEADDR + 0x20);
        data[i].header = 0x1207;
        data[i].footer = 0xDA7A;
    }

    tcp_write(c_pcb, data, read_length*sizeof(*data), 1);

    test_counter++;

    ret_val = Xil_In32(XPAR_AXI_GB_ROTARY_BASEADDR + 4);
    if( ret_val & 0x00000001 ){
        xil_printf("\r\nPulse detected: ");
        Xil_Out32(XPAR_AXI_GB_ROTARY_BASEADDR + 4, ret_val & 0xFFFFFFFE);
        sync.header = 0x1207;
        sync.footer = 0x570C;
        sync.stamp = Xil_In32(XPAR_AXI_GB_ROTARY_BASEADDR + 8);
        sync.data = Xil_In32(XPAR_AXI_GB_ROTARY_BASEADDR + 12);
        tcp_write(c_pcb, &sync, sizeof(sync), 1);
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

void print_app_header()
{
#if (LWIP_IPV6==0)
    xil_printf("\n\r\n\r-----lwIP TCP echo server ------\n\r");
#else
    xil_printf("\n\r\n\r-----lwIPv6 TCP echo server ------\n\r");
#endif
    xil_printf("TCP packets sent to port 6001 will be echoed back\n\r");
}

err_t recv_callback(void *arg, struct tcp_pcb *tpcb,
                               struct pbuf *p, err_t err)
{
    u32 enc_val;
    /* do not read the packet if we are not in ESTABLISHED state */
    if (!p) {
        tcp_close(tpcb);
        tcp_recv(tpcb, NULL);
        return ERR_OK;
    }

    /* indicate that the packet has been received */
    tcp_recved(tpcb, p->len);

    /* echo back the payload */
    /* in this case, we assume that the payload is < TCP_SND_BUF */
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


err_t accept_callback(void *arg, struct tcp_pcb *newpcb, err_t err)
{	
    static int connection = 1;
    u32 ret_val;

    /* set the receive callback for this connection */
    //tcp_recv(newpcb, recv_callback);
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




    /* create new TCP PCB structure */
    pcb = tcp_new_ip_type(IPADDR_TYPE_ANY);
    if (!pcb) {
        xil_printf("Error creating PCB. Out of Memory\n\r");
        return -1;
    }

    /* bind to specified @port */
    err = tcp_bind(pcb, IP_ANY_TYPE, port);
    if (err != ERR_OK) {
        xil_printf("Unable to bind to port %d: err = %d\n\r", port, err);
        return -2;
    }

    /* we do not need any arguments to callback functions */
    tcp_arg(pcb, NULL);

    /* listen for connections */
    pcb = tcp_listen(pcb);
    if (!pcb) {
        xil_printf("Out of memory while tcp_listen\n\r");
        return -3;
    }

    /* specify callback to use for incoming connections */
    tcp_accept(pcb, accept_callback);

    xil_printf("TCP echo server started @ port %d\n\r", port);

    return 0;
}
