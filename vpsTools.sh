#!/bin/bash

#dd ubuntu 20.04 
#bash <(wget --no-check-certificate -qO- 'https://www.moeelf.com/attachment/LinuxShell/InstallNET.sh') -u 20.04 -v 64 -a
#apt update & apt upgrade -y

change_ssh(){
    # Check root privileges
    if [ "$(id -u)" -ne 0 ]; then
      echo "Error: This script must be run as root" >&2
      exit 1
    fi
    
    # Backup SSH config file
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak_$(date +%Y%m%d%H%M%S)
    
    # Comment out all existing Port configurations
    sed -i 's/^Port/#Port/g' /etc/ssh/sshd_config
    
    # Get new port number
    read -p "Enter new SSH port (default 22666): " new_port
    
    # Set default value
    if [ -z "$new_port" ]; then
      new_port=22666
    fi
    
    # Validate port number
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
      echo "Error: Invalid port number. Must be between 1-65535"
      exit 1
    fi
    
    # Check if port is already in use
    if ss -tuln | grep -q ":${new_port}\b"; then
      echo "Error: Port $new_port is already in use"
      exit 1
    fi
    
    # Add new port configuration
    echo "# Modified on $(date)" >> /etc/ssh/sshd_config
    echo "Port $new_port" >> /etc/ssh/sshd_config
    
    # Update firewall rules
    update_firewall() {
      # Try firewalld
      if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --remove-service=ssh
        firewall-cmd --permanent --add-port=$new_port/tcp
        firewall-cmd --reload
        echo "Updated firewalld rules"
        return
      fi
      
      # Try ufw
      if command -v ufw &> /dev/null; then
        ufw allow $new_port/tcp
        ufw deny ssh  # Disable default SSH port
        echo "Updated ufw rules"
        return
      fi
      
      # Try iptables
      if command -v iptables &> /dev/null; then
        iptables -A INPUT -p tcp --dport $new_port -j ACCEPT
        service iptables save 2>/dev/null || iptables-save > /etc/iptables/rules.v4
        echo "Updated iptables rules"
        return
      fi
      
      echo "Warning: No supported firewall detected"
    }
    
    # Update SELinux
    if command -v semanage &> /dev/null; then
      semanage port -a -t ssh_port_t -p tcp $new_port
    fi
    
    # Restart SSH service
    if systemctl restart sshd 2>/dev/null || service ssh restart 2>/dev/null; then
      echo "SSH service restarted"
    else
      echo "Warning: Failed to restart SSH service, please restart manually"
    fi
    
    # Display success message
    echo -e "\n####################################################"
    echo "# SSH port successfully changed to: $new_port"
    echo "# Original config backed up as: /etc/ssh/sshd_config.bak_*"
    echo "# Connect using: ssh -p $new_port user@your-server"
    echo "####################################################"
}

ssh_login_file(){
    echo "not done yet"
}

cert=/root/cert

enable_bbr(){
    sysctl -p|grep bbr && return
    echo net.core.default_qdisc=fq >> /etc/sysctl.conf
    echo net.ipv4.tcp_congestion_control=bbr >> /etc/sysctl.conf
    sysctl -p
}

init(){
    apt update -y && apt install -y wget curl socat ufw && ufw allow 80 && ufw allow 443 && ufw allow 54321
}

install_acme(){
    curl https://get.acme.sh | sh
    acme=~/.acme.sh/acme.sh

    t=0
    while [ $t -lt 30 ];do
        [ -f $acme ] && break
        let t++ && sleep 1
    done
    install_cert
}

install_cert(){
    [ $cert ] || (echo "cert path not exist" && return)
    [ -f $acme ] || (echo "acme not exist" && return)

    [ -f $cert/cert.crt ] && (echo "cert exist" && return)

    mkdir -m 775 $cert
    read -e -p "email(default is burningl@163.com):" email
    read -e -p "domain for cert(default is v.peerknow.top):" domain
    read -e -p "is ipv4?(input nothing=no)" isIPV4
    [ $email ] || email=burningl@163.com
    [ $domain ] || domain=v.peerknow.top

    $acme --register-account -m $email
    # your can switch server:
    # ~/.acme.sh/acme.sh --set-default-ca --server {letsencrypt|buypass|zerossl}
    sleep 8

    if [ $isIPV4 ];then
        $acme --issue --standalone -d $domain
    else 
        $acme --issue --standalone --listen-v6  -d $domain
    fi
    
    t=0
    while [ $t -lt 30 ];do
        $acme list|grep $domain && $acme --installcert --key-file $cert/private.key --fullchain-file $cert/cert.crt -d $domain
        let t++ && sleep 1
    done
    t=0
    while [ $t -lt 30 ];do
      [ -f $cert/cert.crt ] && break
      let t++ && sleep 1
    done
    # $acme --upgrade --auto-upgrade
}

install_docker(){
    docker -v && (echo "docker installed already" && return)
    curl -fsSL https://get.docker.com | sh
    t=0
    while [ $t -lt 30 ];do
      docker -v && break
      let t++ && sleep 1
    done
    # build your own docker img
    # docker build -t x-ui .
}

install_x-ui(){
    read -e -p "x-ui@docker?" isDocker
    [ $isDocker ] || (return bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh))
    docker -v || (echo "docker not installed" && return)
    [ $cert ] || (echo "cert path not exist" && return)

    xpath=/home/data/docker/x-ui
    mkdir -m 775 -p $xpath
    read -e -p "image:" img 
    [ $img ] || img=enwaiax/x-ui
    docker run -itd --network=host --name x-ui --restart=unless-stopped -v $xpath/db/:/etc/x-ui/ -v $cert:$cert $img
    t=0
    while [ $t -lt 30 ];do
      docker ps|grep x-ui && break
      let t++ && sleep 1
    done
}
######### insert in xui config ########
#"outbounds": [
#{
#      "tag": "chatGPT_proxy",
#      "protocol": "socks",
#      "settings": {
#        "servers": [
#          {
#            "address": "127.0.0.1",
#            "port": 40000
#          }
#        ]
#      }
#},

#"rules": [
#      {
#        "type": "field",
#        "outboundTag": "chatGPT_proxy",
#        "domain": [
#          "chat.openai.com",
#          "ip138.com"
#        ]
#      },
#################################

install_gost(){
    [ -f gost.sh ] && return
    link=https://raw.githubusercontent.com/KANIKIG/Multi-EasyGost/master/gost.sh
    wget --no-check-certificate -O gost.sh $link && chmod +x gost.sh && ./gost.sh
    t=0
    while [ $t -lt 30 ];do
      [ -f gost.sh ] && break
      let t++ && sleep 1
    done
}

install_cloudflare-warp(){
    curl ifconfig.me --proxy socks5://127.0.0.1:40000 && return
    # add universe to /etc/apt/source.list by copy ` main$` line then `s/main/universe/` when got error for apt install lsb_release
    curl https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    
    ver=$(lsb_release -sc) || read -e -p "input nothing=bullseye" ver
    [ $ver ] || ver=bullseye
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $ver main" | tee /etc/apt/sources.list.d/cloudflare-client.list

    apt update && apt install cloudflare-warp && warp-cli register && warp-cli set-mode proxy && warp-cli connect && warp-cli enable-always-on
    t=0
    while [ $t -lt 30 ];do
      curl ifconfig.me --proxy socks5://127.0.0.1:40000 && break
      let t++ && sleep 1
    done
}




enable_IPV4(){
    cat /etc/resolv.conf | grep 2001:67c:2b0::6 && return
    sed -i "s@^\(nameserver.*\)@#\1@" /etc/resolv.conf
    printf "%s\n" "nameserver 2001:67c:2b0::4" "nameserver 2001:67c:2b0::6" >> /etc/resolv.conf
}

install_trojan-go(){
    # install without docker:
    # source <(curl -sL https://git.io/trojan-install)
    # remove:
    # source <(curl -sL https://git.io/trojan-install) --remove
    docker -v || (echo "docker not installed" && exit)
    [ $cert ] || (echo "cert path not exist" && exit)

    mpath=/home/data/docker/mariadb
    mkdir -m 775 -p $mpath
    docker run --name trojan-mariadb --restart=always -p 3306:3306 -v $mpath:/var/lib/mysql -e MYSQL_ROOT_PASSWORD=lee@mariadb -e MYSQL_ROOT_HOST=% -e MYSQL_DATABASE=trojan -d mariadb:10.2 && \
    docker run -itd --name trojan -v $cert:$cert --net=host --restart=always --privileged jrohy/trojan init && \
    echo "run 'trojan' in container"
    docker exec -it trojan bash
    # optional: systemctl enable trojan-web && systemctl start trojan-web
}


install_filebrowser(){
  docker -v||(echo "docker missing"&&return)
  docker ps -a|grep filebrowser && (echo "already installed"&&return)
  read -e -p "filebrowser path(input nothing for default):" path
  [ $path ] || path="/home/data/docker/filebrowser"
  read -e -p "user name:" usr
  [ $usr ] || usr=lee
  read -e -p "group name:" grp
  [ $grp ] || grp=root
  read -e -p "port:" port
  [ $port ] || port=80
  read -e -p "image:" img
  [ $img ] || img=filebrowser/filebrowser
  docker run -d --name filebrowser --restart=always -v $path:/srv -e PUID=$usr -e PGID=$grp -p $port:80 $img
}

while true; do
  echo "0.autoFlow(1,2,3,5,4,6); 1.enable bbr; 2.enable_IPV4; 3.init; 4.install cert; 5.install docker; a.install x-ui; b.install filebrowser"
  echo "7.install gost(forward rules:41043/ws->40143/ws@domain); 8.install cloudflare-warp; 9.install trojan-go"
  echo "s.change ssh port; p.change ssh login method"
  read -e -p "input :" num
  case $num in
    [s]* ) change_ssh;;
    [p]* ) ssh_login_file;;
    [1]* ) enable_bbr;;
    [2]* ) enable_IPV4;;
    [3]* ) init;;
    [4]* ) install_acme;;
    [5]* ) install_docker;;
    [a]* ) install_x-ui;;
    [b]* ) install_filebrowser;;
    [7]* ) install_gost;;
    [8]* ) install_cloudflare-warp;;
    [9]* ) install_trojan-go;;
    [0]* ) enable_bbr && enable_IPV4 && init && install_docker && install_acme && install_x-ui;;
    * ) echo "input error";;
  esac
done
				
