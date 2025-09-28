config defaults
        option input 'DROP'
        option output 'ACCEPT'
        option forward 'DROP'
        option synflood_protect '1'
        option custom_chains '1'

config zone
        option name 'lan'
        list   network 'lan'
        option input 'ACCEPT'
        option output 'ACCEPT'
        option forward 'DROP'

config zone
       option name 'wan'
       list   network 'wan'
       option input 'DROP'
       option output 'ACCEPT'
       option forward 'DROP'
       option masq '1'
       option mtu_fix '1'

config forwarding
        option src 'lan'
        option dest 'wan'

config rule
        option name 'Allow-DHCP-From-LAN'
        option src 'lan'
        option proto 'udp'
        option dest_port '67-68'
        option target 'ACCEPT'

config rule
        option name 'Allow-DNS-From-LAN'
        option src 'lan'
        option proto 'tcp udp'
        option dest_port '53'
        option target 'ACCEPT'

config rule
        option name 'Allow-Established-Related'
        option src '*'
        option dest '*'
        option proto 'all'
        option family 'any'
        option target 'ACCEPT'
        option extra '-m conntrack --ctstate RELATED,ESTABLISHED'

