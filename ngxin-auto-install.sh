#!/bin/bash

# Author: 1spacebox.com
# Description: Nginx Mainline版本, 自动编译安装.
# route: 本机如已安装nginx,支持卸载和删除nginx. 已添加二进制, 已添加系统服务.
# Version: 1.0
# Date: 2023-3-31

# env
nginx_install_path="/opt/nginx"
nginx_download_path="/opt"
Blue="\033[36m"
Green="\033[32m"
Red="\033[31m"
OK="${Green}[OK]${Font}"
ERROR="${Red}[ERROR]${Font}"
Font="\033[0m"

function print_ok() {
    echo -e "${OK} $1 ${Font}"
}
function print_error() {
    echo -e "${ERROR} $1 ${Font}"
}

judge() {
    if [[ 0 -eq $? ]]; then
        print_ok "$1 成功"
        sleep 1
    else
        print_error "$1 失败"
        exit 1
    fi
}

# 更新系统和包
function update_system_and_packages() {
    echo "正在更新系统和包..."
    if (sudo apt update && sudo apt upgrade -y); then
        judge "系统和包更新="
    fi
}

# 安装nginx依赖
function install_nginx_dependencies() {
    echo "正在安装nginx依赖..."
    if (sudo apt install -y build-essential libpcre3-dev zlib1g-dev libssl-dev libxml2-dev libgd-dev); then
        judge "nginx依赖安装="
    fi
}

# 下载新版Nginx
function down_nginx() {
    # 获取最新nginx Mainline版本号
    if latest_version=$(curl -s https://nginx.org/en/download.html | grep -oP 'Mainline version.*?nginx-(.*?).tar.gz' | sed 's/.*nginx-//' | sed 's/.tar.gz.*//'); then
        judge "最新 Nginx 版本: $latest_version 获取="
    fi
    # 下载Nginx源码
    if (sudo wget https://nginx.org/download/nginx-"$latest_version".tar.gz -P $nginx_download_path); then
        judge "Nginx下载 : $latest_version 路径: $nginx_download_path/nginx-$latest_version"
    fi
    # 解压源码
    if (sudo tar -C "$nginx_download_path" -zxvf "$nginx_download_path"/nginx-"$latest_version".tar.gz); then
        print_ok "Nginx-$latest_version.tar.gz解压成功"
    else
        print_error "Nginx-$latest_version.tar.gz解压失败"
    fi

}

# 编译nginx
function compile_nginx() {
    echo "正在编译nginx..."
    cd $nginx_download_path/nginx-"$latest_version" || exit
    ./configure --prefix=$nginx_install_path \
        --pid-path=$nginx_install_path/run/nginx.pid \
        --lock-path=$nginx_install_path/run/nginx.lock \
        --http-client-body-temp-path=$nginx_install_path/temp \
        --http-proxy-temp-path=$nginx_install_path/temp \
        --http-fastcgi-temp-path=$nginx_install_path/temp \
        --http-uwsgi-temp-path=$nginx_install_path/temp \
        --http-scgi-temp-path=$nginx_install_path/temp \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_realip_module \
        --with-stream \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        --with-stream_realip_module
    if (make && make install); then
        judge "Nginx编译安装="
    fi
    if (sudo rm -rf "$nginx_download_path"/nginx-"$latest_version".tar.gz); then
    judge ""$nginx_download_path"/nginx-"$latest_version".tar.gz 删除="
    fi
    if (sudo rm -rf "$nginx_download_path"/nginx-"$latest_version"); then
    judge ""$nginx_download_path"/nginx-"$latest_version" 删除="
    fi

    echo -e "\033[1m\033[31m----请选择操作-----(1或者2)\033[0m"
    echo -e "1. \033[32m安装nginx系统服务文件\033[0m"
    echo -e "2. \033[34m安装nginx+web系统服务文件\033[0m"
    read -r "input2"
    case "$input2" in
    1)
        create_nginx_file
        ;;
    2)
        create_nginx_file
        create_nginx_web_file
        ;;
    *)
        # 其他输入 报错 退出
        echo "无效输入 请输入 1 or 2"
        exit 1
        ;;
    esac
}

# 创建nginx服务文件
function create_nginx_file() {
    echo "正在创建nginx服务文件..."
    if cat >/etc/systemd/system/nginx.service <<EOF; then
    [Unit]
    Description=The NGINX for xray
    After=syslog.target network-online.target remote-fs.target nss-lookup.target
    Wants=network-online.target

    [Service]
    Type=forking
    PIDFile=$nginx_install_path/run/nginx.pid
    ExecStartPre=$nginx_install_path/sbin/nginx -t
    ExecStart=$nginx_install_path/sbin/nginx
    ExecReload=$nginx_install_path/sbin/nginx -s reload
    ExecStop=/bin/kill -s QUIT $MAINPID
    PrivateTmp=true

    [Install]
    WantedBy=multi-user.target
EOF
        print_ok "nginx系统服务文件创建成功"
    else
        print_error "nginx系统服务文件创建失败 请手动创建"
        return 1
    fi
}

# 创建nginx_web服务文件
function create_nginx_web_file() {
    echo "正在创建nginx_web服务文件..."
    if (sudo mkdir -p $nginx_install_path/web); then
        print_ok "$nginx_install_path/web 创建成功"
    else
        print_error "$nginx_install_path/web 创建失败"
    fi
    if cat >/etc/systemd/system/nginx_web.service <<EOF; then
    [Unit]
    Description=The NGINX for web
    After=syslog.target network-online.target remote-fs.target nss-lookup.target
    Wants=network-online.target

    [Service]
    Type=forking
    PIDFile=$nginx_install_path/run/nginx.pid
    ExecStartPre=$nginx_install_path/sbin/nginx -t
    ExecStart=$nginx_install_path/sbin/nginx -c /web/*.conf
    ExecReload=$nginx_install_path/sbin/nginx -s reload
    ExecStop=/bin/kill -s QUIT $MAINPID
    PrivateTmp=true

    [Install]
    WantedBy=multi-user.target
EOF
        print_ok "nginx_web系统服务文件创建成功"
    else
        print_error "nginx_web系统服务文件创建失败 请手动创建"
        return 1
    fi
}

# 复制二进制文件到/usr/local/bin
function mv_nginx_bin() {
    echo "移动nginx二进制文件.."
    if (sudo cp $nginx_install_path/sbin/nginx /usr/local/bin); then
        print_ok "nginx二进制文件移动成功 路径: usr/local/bin"
    else
        print_error "nginx二进制文件移动失败 请手动移动"
    fi
}

# 启动nginx服务
function start_nginx_service() {
    echo -e "\033[1m\033[31m----请选择操作-----(1或者2)\033[0m"
    echo -e "1. \033[32mnginx系统服务重启+开机自启\033[0m"
    echo -e "2. \033[34mnginx+web系统服务重启+开机自启\033[0m"
    read -r "input3"
    case "$input3" in
    1)
        echo "正在启动nginx服务..."
        if (
            sudo systemctl daemon-reload
            sudo systemctl restart nginx
            sudo systemctl enable nginx
        ); then
            print_ok "nginx服务启动成功 设置开机自启服务成功"
        else
            print_error "nginx服务启动失败.. 请检查"
        fi
        ;;
    2)
        echo "正在启动nginx服务..."
        if (
            sudo systemctl daemon-reload
            sudo systemctl restart nginx
            sudo systemctl restart nginx_web
            sudo systemctl enable nginx
            sudo systemctl enable nginx_web
        ); then
            print_ok "nginx服务启动成功 设置开机自启服务成功"
        else
            print_error "nginx服务启动失败.. 请检查"
        fi
        ;;
    *)
        # 其他输入 报错 退出
        echo "无效输入 请输入 1 or 2"
        exit 1
        ;;
    esac
}

function start_nginx_web_service() {
    echo "正在启动nginx服务..."
    if (
        sudo systemctl daemon-reload
        sudo systemctl restart nginx_web
        sudo systemctl enable nginx_web
    ); then
        print_ok "nginx_web服务启动成功 设置开机自启服务成功"
    else
        print_error "nginx_web服务启动失败.. 请检查"
    fi
}

# echo
function end_echo() {
    clear
    echo -e "\033[1m\033[33mnginx已经安装完毕 信息如下:\033[0m"
    echo -e "\033[1mnginx 安装: \033[0m\033[4m${nginx_install_path}\033[0m"
    echo -e "\033[1mnginx 二进制文件: \033[0m\033[4m/usr/local/bin\033[0m"
    echo -e "\033[1mnginx 系统服务文件: \033[0m\033[4m/etc/systemd/system/nginx.service\033[0m"
    echo -e "\033[1mNginx系统服务已经安装.. 并且启用开机自启.. 你可以直接shell输入 nginx -v\033[0m"
    echo -e "\033[32m power by: 1spacebox.com \033[0m"
}

# 查找并删除 nginx 目录
function del_nginx() {
    nginx_dir=$(sudo find / -name "nginx")
    nginx_service_dir=$(sudo find / -name "nginx.service")
    if [ -z "$nginx_dir" ]; then
        print_error "未找到 nginx 目录/文件: $nginx_dir"
    else
        print_ok "已找到 nginx 目录/文件: $nginx_dir"
    fi
    if (sudo rm -rf "$nginx_dir"); then
        print_ok "已删除 nginx 目录/文件: $nginx_dir"
    else
        print_error "删除 nginx 目录/文件失败"
    fi
    if [ -z "$nginx_service_dir" ]; then
        print_ok "已找到 nginx 系统服务文件: $nginx_service_dir"
    else
        print_error "未找到 nginx 系统服务文件"
    fi
}

# do it
echo -e "\033[1m\033[31m----请选择操作-----(1或者2)\033[0m"
echo -e "1. \033[32m已经安装nginx, 开始自动卸载安装\033[0m"
echo -e "2. \033[34m没有安装nginx, 开始自动安装\033[0m"
read -r "input"
case "$input" in
1)
    echo -e "\033[32m你选择了操作1. 接下来会开始关闭nginx服务.. 卸载.. 安装..\033[0m"
    # 检查nginx是否安装, 有则卸载.
    if (dpkg -l | grep nginx | awk '{print $1,$2}' | grep "^ii" >/dev/null); then
        # 卸载nginx
        print_ok "检测到已安装nginx.. 开始卸载.."
        sudo apt purge nginx -y
    else
        # 停止nginx系统服务
        if (sudo systemctl stop nginx); then
            print_ok "nginx 服务关闭成功"
        else
            print_error "nginx 服务关闭失败"
        fi
        echo "nginx 服务关闭失败, 请确认是否已安装nginx并且有nginx系统服务文件"
    fi
    update_system_and_packages
    del_nginx
    install_nginx_dependencies
    down_nginx
    compile_nginx
    mv_nginx_bin
    start_nginx_service
    end_echo
    ;;
2)
    echo -e "\033[34m你选择了操作2. 接下来自动安装nginx依赖.. nginx.. 系统服务..\033[0m"

    update_system_and_packages
    del_nginx
    install_nginx_dependencies
    down_nginx
    compile_nginx
    mv_nginx_bin
    start_nginx_service
    end_echo
    ;;
*)
    # 其他输入 报错 退出
    echo "无效输入 请输入 1 or 2"
    exit 1
    ;;
esac