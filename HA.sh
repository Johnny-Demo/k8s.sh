#!/bin/bash
##############################################
#
# k8s 高可用和负载均衡
#
##############################################

# Author: Johnny
# Email: xxx@163.com
# Date: 05/25/2022
# File name: HA.sh

# 定义变量（后面调用方便些）
ip_list="192.168.200.4 192.168.200.5"


# 安装 keepalived 和 haproxy 并修改配置文件参数
yum -y install keepalived haproxy
cat > /etc/keepalived/keepalived.conf << EOF
! Configuration File for keepalived

global_defs {
   router_id LVS_DEVEL

# 添加如下内容
   script_user root
   enable_script_security
}

vrrp_script check_haproxy {
    script "/etc/keepalived/check_haproxy.sh"         # 检测脚本路径
    interval 3
    weight -2 
    fall 10
    rise 2
}

vrrp_instance VI_1 {
    state MASTER            # MASTER
    interface ens33         # 本机网卡名
    virtual_router_id 51
    priority 100             # 权重100
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass 1111
    }
    virtual_ipaddress {
        192.168.200.16      # 虚拟IP
    }
    track_script {
        check_haproxy       # 模块
    }
}
EOF

cat > /etc/haproxy/haproxy.cfg << EOF
#---------------------------------------------------------------------
# Example configuration for a possible web application.  See the
# full configuration options online.
#
#   http://haproxy.1wt.eu/download/1.4/doc/configuration.txt
#
#---------------------------------------------------------------------

#---------------------------------------------------------------------
# Global settings
#---------------------------------------------------------------------
global
    # to have these messages end up in /var/log/haproxy.log you will
    # need to:
    #
    # 1) configure syslog to accept network log events.  This is done
    #    by adding the '-r' option to the SYSLOGD_OPTIONS in
    #    /etc/sysconfig/syslog
    #
    # 2) configure local2 events to go to the /var/log/haproxy.log
    #   file. A line like the following can be added to
    #   /etc/sysconfig/syslog
    #
    #    local2.*                       /var/log/haproxy.log
    #
    log         127.0.0.1 local2

    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon

    # turn on stats unix socket
    stats socket /var/lib/haproxy/stats

#---------------------------------------------------------------------
# common defaults that all the 'listen' and 'backend' sections will
# use if not designated in their block
#---------------------------------------------------------------------
defaults
    mode                    http
    log                     global
    option                  httplog
    option                  dontlognull
    option http-server-close
    option forwardfor       except 127.0.0.0/8
    option                  redispatch
    retries                 3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout http-keep-alive 10s
    timeout check           10s
    maxconn                 3000

#---------------------------------------------------------------------
# main frontend which proxys to the backends
#---------------------------------------------------------------------
frontend  kubernetes-apiserver
    mode                        tcp
    bind                        *:16443
    option                      tcplog
    default_backend             kubernetes-apiserver

#---------------------------------------------------------------------
# static backend for serving up images, stylesheets and such
#---------------------------------------------------------------------
listen stats
    bind            *:1080
    stats auth      admin:awesomePassword
    stats refresh   5s
    stats realm     HAProxy\ Statistics
    stats uri       /admin?stats

#---------------------------------------------------------------------
# round robin balancing between the various backends
#---------------------------------------------------------------------
backend kubernetes-apiserver
    mode        tcp
    balance     roundrobin
    server  master1 192.168.200.3:6443 check
    server  master2 192.168.200.4:6443 check
    server  master3 192.168.200.5:6443 check
EOF


touch /etc/keepalived/check_haproxy.sh
cat > /etc/keepalived/check_haproxy.sh << EOF
#!/bin/sh
# HAPROXY down
A=`ps -C haproxy --no-header | wc -l`
if [ $A -eq 0 ]
then
systmectl start haproxy
if [ ps -C haproxy --no-header | wc -l -eq 0 ]
then
killall -9 haproxy
echo "HAPROXY down" | mail -s "haproxy"
sleep 3600
fi 
fi
EOF

chmod 777 /etc/keepalived/check_haproxy.sh
systemctl enable keepalived && systemctl start keepalived
systemctl enable haproxy && systemctl start haproxy 


for a in $ip_list1
do
   ssh root@$a yum -y install keepalived haproxy 
   scp /etc/keepalived/keepalived.conf $a:/etc/keepalived/
   scp /etc/haproxy/haproxy.cfg $a:/etc/haproxy
   scp /etc/keepalived/check_haproxy.sh $a:/etc/keepalived/
   scp chmod 777 /etc/keepalived/check_haproxy.sh $a:/etc/keepalived/ 
   ssh root@$a find -name 'keepalived.conf' | xargs perl -pi -e 's|state MASTER|state BACKUP|g'
   ssh root@$a systemctl enable keepalived && systemctl start keepalived
   ssh root@$a systemctl enable haproxy && systemctl start haproxy 
done


list1=192.168.200.4

for b in $list1
do
  ssh root@$b find -name 'keepalived.conf' | xargs perl -pi -e 's|priority 100|priority 99|g'
  ssh root@$b systemctl restart keepalived
done


list2=192.168.200.5

for c in $list2
do
  ssh root@$c find -name 'keepalived.conf' | xargs perl -pi -e 's|priority 100|priority 98|g'
  ssh root@$c systemctl restart keepalived
done

