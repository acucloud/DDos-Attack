#!/bin/bash
USERNAME=""
LOGFILE=InstallV2ray.log
V2RAYPORT=              #前端设置的inside_port
SSHPORT=8888

## v2ray相关配置
NODEID=""
DOMAIN=""                           #节点域名
#PANELKEY=""             # 表示 MU KEY
DOWNWITHPANEL="0"                     # 前端面板异常下线时，0 为节点端不下线、1 为节点跟着下线
MYSQLHOST=""          # 数据库访问域名
MYSQLDBNAME=""             # 数据库名
MYSQLUSER=""                 # 数据库用户名
MYSQLPASSWD=""         # 数据库密码
MYSQLPORT=""                      # 数据库连接端口
SPEEDTESTRATE=""                     # 测速周期
PANELTYPE=""                         # 面板类型，0 为 ss-panel-v3-mod、1 为 SSRPANEL
USEMYSQL=""                         # 连接方式，0 为 webapi，1 为 MySQL 数据库连接，请注意 SSRPANEL 必须使用数据库连接
CFKEY=""                        # cloudflare key
CFEMAIL=""                      # cloudflare email

#root身份登录后下载必要组件
function InitDownload()
{
    echo "更新列表" | tee -a $LOGFILE
    apt update
    echo "升级" | tee -a $LOGFILE
    apt upgrade
    echo "安装curl vim sudo fish" | tee -a $LOGFILE
    apt install -y vim curl sudo fish
    if test $? -eq 0
    then
        echo "安装完成" | tee -a $LOGFILE
        return 0
    else
        echo "安装失败" | tee -a $LOGFILE
        return 1
    fi
}

#root身份配置
function InitConf()
{
    echo "修改root密码和登录shell" | tee -a $LOGFILE
    passwd
    chsh /usr/bin/fish
    echo "创建用户" | tee -a $LOGFILE
    useradd -m $USERNAME -s /usr/bin/fish
    if test $? -eq 0
    then
        echo "创建成功,请输入密码" | tee -a $LOGFILE
        passwd $USERNAME
    else
        echo "创建失败" | tee -a $LOGFILE
        return 1
    fi
    echo "修改远程登录相关项" | tee -a $LOGFILE
    sed -i "/Port 22/i Port $SSHPORT" /etc/ssh/sshd_config
    sed -i "/Port 22/i PermitRootLogin no" /etc/ssh/sshd_config
    sed -i "/Port 22/i PasswordAuthentication yes" /etc/ssh/sshd_config
    systemctl restart sshd
    echo "修改完成，下次在$SSHPORT处使用$USERNAME登录" | tee -a $LOGFILE
    echo "visudo 3s后手动添加用户到sudoer" | tee -a $LOGFILE
    sleep 3s
    visudo
    return 0
}

function InstallV2ray()
{
    echo "V2ray相关开始" | tee -a $LOGFILE
    echo "需要安装 Caddy? yes/no" | tee -a $LOGFILE
    read ans
    if test $ans = "yes"
    then
        curl https://getcaddy.com | bash -s personal dyndns,tls.dns.cloudflare
        if test $? -eq 0
        then
            echo "安装完成，接下来进行配置" | tee -a $LOGFILE
            curl -s https://raw.githubusercontent.com/mholt/caddy/master/dist/init/linux-systemd/caddy.service -o /etc/systemd/system/caddy.service
            mkdir /etc/caddy
            chown -R root:www-data /etc/caddy
            if test -e /etc/caddy/Caddyfile
            then
                rm -ir /etc/caddy/Caddyfile
            else
                touch /etc/caddy/Caddyfile
            fi
            mkdir /etc/ssl/caddy
            chown -R www-data:root /etc/ssl/caddy
            chmod 0770 /etc/ssl/caddy
            mkdir /var/www
            chown www-data:www-data /var/www
            echo "$USERNAME.$DOMAIN{" >> /etc/caddy/Caddyfile
            echo "    root /var/www" >> /etc/caddy/Caddyfile
            echo "    log /var/www/caddy.log" >> /etc/caddy/Caddyfile
            echo "    proxy /v2ray 127.0.0.1:$V2RAYPORT {" >> /etc/caddy/Caddyfile
            echo "        websocket" >> /etc/caddy/Caddyfile
            echo "        header_upstream -Origin" >> /etc/caddy/Caddyfile
            echo "    }" >> /etc/caddy/Caddyfile
            echo "    gzip" >> /etc/caddy/Caddyfile
            echo "    tls $CFEMAIL {" >> /etc/caddy/Caddyfile
            echo "        protocols tls1.0 tls1.2" >> /etc/caddy/Caddyfile
            echo "        # remove comment if u want to use cloudflare ddns" >> /etc/caddy/Caddyfile
            echo "        dns cloudflare" >> /etc/caddy/Caddyfile
            echo "    }" >> /etc/caddy/Caddyfile
            echo "}" >> /etc/caddy/Caddyfile
            sed -i "s/;AmbientCapabilities=CAP_NET_BIND_SERVICE/AmbientCapabilities=CAP_NET_BIND_SERVICE/g" /etc/systemd/system/caddy.service
            sed -i "/Environment=CADDYPATH=\/etc\/ssl\/caddy/a Environment=CLOUDFLARE_API_KEY=$CFKEY" /etc/systemd/system/caddy.service
            sed -i "/Environment=CADDYPATH=\/etc\/ssl\/caddy/a Environment=CLOUDFLARE_EMAIL=$CFEMAIL" /etc/systemd/system/caddy.service
            systemctl daemon-reload
            systemctl enable caddy.service
            systemctl start caddy.service
            echo "完成caddy的配置" | tee -a $LOGFILE
        else
            echo "安装失败,跳过此步骤，如有需要自行手动安装" | tee -a $LOGFILE
            return 1
        fi
    fi

    echo "安装V2ray,数据库对接方式" | tee -a $LOGFILE
    bash <(curl -L -s  https://raw.githubusercontent.com/v2rayv3/pay-v2ray-sspanel-v3-mod_Uim-plugin/master/install-release.sh) \
        --nodeid $NODEID \
        --mysqlhost $MYSQLHOST --mysqldbname $MYSQLDBNAME --mysqluser $MYSQLUSER --mysqlpasswd $MYSQLPASSWD --mysqlport $MYSQLPORT \
        --downwithpanel $DOWNWITHPANEL --speedtestrate $SPEEDTESTRATE --paneltype $PANELTYPE --usemysql $USEMYSQL --cfemail $CFEMAIL --cfkey $CFKEY
    echo "安装完成，下面配置开启V2RAY" | tee -a $LOGFILE
    sed -i "1,87d" /etc/v2ray/config.json
    sed -i "1 i {" /etc/v2ray/config.json
    systemctl enable v2ray
    systemctl start v2ray
    return 0
}


function main()
{
    if test -e $LOGFILE
    then
        rm -ir $LOGFILE
    else
        touch $LOGFILE
    fi

    if test $? -ne 0
    then
        echo "log文件创建失败，不会记录到文件，不影响后续执行"
    fi
    echo "输入用户名，新系统作为创建用户依据，老系统作为caddy域名依据,也就是你节点域名地址的前缀: " | tee -a $LOGFILE
    read USERNAME
    echo "输入NODE ID：" | tee -a $LOGFILE
    read NODEID
    while getopts "hiv" optname
    do
        case "$optname" in
            "h")
                echo "-i 进入新系统后进行初始设置"
                echo "-v 安装配置v2ray后端"
                ;;
            "i")
                echo "进行裸机安装配置" | tee -a $LOGFILE
                InitDownload
                InitConf
                ;;
            "v")
                echo "安装配置v2ray" | tee -a $LOGFILE
                InstallV2ray
                ;;
            \?)
                echo "无效的选项"
      esac
  done
}


main $1
