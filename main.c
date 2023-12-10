#include <stdio.h>
#include "xparameters.h"
#include "netif/xadapter.h"

#include "platform.h"
#include "platform_config.h"
#include "xil_printf.h"


#include "lwip/tcp.h"
#include "xil_cache.h"

int start_application();
int transfer_data();
void tcp_fasttmr(void);
void tcp_slowtmr(void);

void lwip_init();

extern volatile int TcpFastTmrFlag;
extern volatile int TcpSlowTmrFlag;
static struct netif server_netif;
struct netif *echo_netif;

void print_ip(char *msg, ip_addr_t *ip)
{
    print(msg);
    xil_printf("%d.%d.%d.%d\n\r", ip4_addr1(ip), ip4_addr2(ip), 
            ip4_addr3(ip), ip4_addr4(ip));
}

void print_ip_settings(ip_addr_t *ip, ip_addr_t *mask, ip_addr_t *gw)
{
    print_ip("Board IP: ", ip);
    print_ip("Netmask : ", mask);
    print_ip("Gateway : ", gw);
}

int main()
{
    ip_addr_t ipaddr, netmask, gw;

    // MAC address setting
    unsigned char mac_ethernet_address[] =
    { 0x00, 0x0a, 0x35, 0x00, 0x01, 0x02 };

    echo_netif = &server_netif;

    // Platform initialization
    init_platform();

    // IP settings
    IP4_ADDR(&ipaddr,  192, 168,  10, 13);
    IP4_ADDR(&netmask, 255, 255, 255,  0);
    IP4_ADDR(&gw,      192, 168,  10,  1);

    lwip_init();

    /* Add network interface to the netif_list, and set it as default */
    if (!xemac_add(echo_netif, &ipaddr, &netmask,
                        &gw, mac_ethernet_address,
                        PLATFORM_EMAC_BASEADDR)) {
        xil_printf("Error adding N/W interface\n\r");
        return -1;
    }

    netif_set_default(echo_netif);

    // Interrupt
    platform_enable_interrupts();

    // netif setting
    netif_set_up(echo_netif);

    // ip setting
    print_ip_settings(&ipaddr, &netmask, &gw);


    // app
    start_application();

    /* receive and process packets */
    while (1) {
        if (TcpFastTmrFlag) {
            tcp_fasttmr();
            TcpFastTmrFlag = 0;
        }
        if (TcpSlowTmrFlag) {
            tcp_slowtmr();
            TcpSlowTmrFlag = 0;
        }
        xemacif_input(echo_netif);
        transfer_data();
    }
  

    cleanup_platform();

    return 0;
}
