#!/bin/bash

# 定义颜色
re="\033[0m"
red="\033[1;91m"
green="\e[1;32m"
yellow="\e[1;33m"
purple="\e[1;35m"
red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }
reading() { read -p "$(red "$1")" "$2"; }

USERNAME=$(whoami) && \
WORKDIR="/home/${USERNAME}/.nezha-dashboard"

[[ "$HOSTNAME" == "s1.ct8.pl" ]] && WORKDIR="${WORKDIR}" || WORKDIR="${WORKDIR}"
[ -d "$WORKDIR" ] || (mkdir -p "$WORKDIR" && chmod 777 "$WORKDIR")

download_nezha() {
    # 检查是否指定版本
    if [ -z "$VERSION" ]; then
        echo "未指定版本，下载最新版本..."
        DOWNLOAD_LINK="https://github.com/ansoncloud8/am-nezha-freebsd/releases/latest/download/nezha-dashboard.tar.gz"
    else
        echo "指定版本为：$VERSION"
        DOWNLOAD_LINK="https://github.com/ansoncloud8/am-nezha-freebsd/releases/download/${VERSION}/nezha-dashboard.tar.gz"
    fi

    if [ -e "$FILENAME" ]; then
        echo "$FILENAME 已存在，跳过下载"
    else
        echo "正在下载文件..."
        FILENAME="$WORKDIR/nezha-dashboard.tar.gz"
        if ! wget -q -O "$FILENAME" "$DOWNLOAD_LINK"; then
            echo "error: 文件 $FILENAME 下载失败。"
            exit
        fi
        echo "已成功下载 $FILENAME"
    fi

    echo "正在解压文件..."
    if ! tar -zxvf "$FILENAME" -C "$WORKDIR" > /dev/null 2>&1; then
        echo "error: 解压失败，请检查文件或重试。"
        exit
    fi
    echo "解压成功。"

    if [ -e "$WORKDIR/nezha-dashboard" ]; then
	       mv $WORKDIR/nezha-dashboard ${WORKDIR}/dashboard
	       chmod +x ${WORKDIR}/dashboard
								rm -f $WORKDIR/data/config.yaml
        echo "文件夹已重命名为 dashboard。"
    else
        echo "error: 解压后的文件夹不存在，可能解压失败或文件结构已更改。"
        exit
    fi
				
	#echo "正在清理下载文件..."
	rm -f "$FILENAME";
				
    return 0
}

generate_config() {
    echo
    echo "初始化nezha-dashboard配置"

    if [ -e "$WORKDIR/data/config.yaml" ]; then
        echo "已初始化nezha-dashboard配置"
    else
        nohup ${WORKDIR}/dashboard >/dev/null 2>&1 &
        sleep 5

        dashboard_pid=$(ps aux | grep "${WORKDIR}/dashboard" | grep -v 'grep' | awk '{print $2}')
        if [ -n "$dashboard_pid" ]; then
            kill -9 "$dashboard_pid"
            echo "初始化nezha-dashboard配置成功"
        else
            if [ -e "$WORKDIR/data/config.yaml" ]; then
                echo "初始化nezha-dashboard配置成功。"
            else
                echo "dashboard未正常启动，初始化失败"
                exit 1
            fi
        fi
    fi

    printf "请输入站点访问端口: "
    read -r nz_site_port

    if [ -z "$nz_site_port" ]; then
        echo "error! 所有选项都不能为空"
        rm -rf ${WORKDIR}
        return 1
    fi

    if [ -e "${WORKDIR}/data/config.yaml" ]; then
								sed -i '' "s/8008/${nz_site_port}/" ${WORKDIR}/data/config.yaml
        echo "端口已更新为: ${nz_site_port}"
    else
        echo "配置文件不存在，更新端口失败"
        return 1
    fi
}


generate_run() {
    cat > ${WORKDIR}/start.sh << EOF
#!/bin/bash
pgrep -f '$WORKDIR/dashboard' | xargs -r kill
cd ${WORKDIR}
exec ${WORKDIR}/dashboard >/dev/null 2>&1
EOF
    chmod +x ${WORKDIR}/start.sh
}

run_nezha(){
    nohup ${WORKDIR}/start.sh >/dev/null 2>&1 &
    IP_ADDRESS=$(devil vhost list public | awk '/Public addresses/ {flag=1; next} flag && $1 ~ /^[0-9.]+$/ {print $1; exit}' | xargs echo -n)
    printf "nezha-dashboard已经准备就绪，请按下回车键启动\n"
    read
    printf "正在启动nezha-dashboard，请耐心等待...\n"
    sleep 3
    if pgrep -f "$WORKDIR/dashboard" > /dev/null; then
        echo "nezha-dashboard 已启动，请使用浏览器访问 http://${IP_ADDRESS}:${nz_site_port} 进行进一步配置。"
        echo "如果你配置了 Proxy 或者 Cloudflared Argo Tunnel，也可以使用域名访问 nezha-dashboard。"
        echo 
    else
        rm -rf "${WORKDIR}"
        echo "nezha-dashboard启动失败，请检查端口开放情况，并保证参数填写正确，请再重新安装！"
    fi
}

check_and_run() {
    if pgrep -f '$WORKDIR/dashboard' > /dev/null; then
        echo "程序已运行"
        exit
    fi
}

install_nezha() {
	echo -e "${yellow}开始运行前，请确保在面板${purple}已开放1个tcp端口${re}"
	echo -e "${yellow}面板${purple}Additional services中的Run your own applications${yellow}已开启为${purplw}Enabled${yellow}状态${re}"
	reading "\n确定继续安装吗？【y/n】: " choice
	case "$choice" in
	[Yy])
	  cd $WORKDIR
	  check_and_run
	  download_nezha && wait
	  generate_run
	  generate_config
	  run_nezha && sleep 3
	;;
	[Nn]) exit 0 ;;
	*) red "无效的选择，请输入y或n" && menu ;;
  esac
}

uninstall_nezha() {
  reading "\n确定要卸载吗？【y/n】: " choice
    case "$choice" in
       [Yy])
          kill -9 $(ps aux | grep '$WORKDIR/dashboard' | awk '{print $2}')
		  echo "删除安装目录: $WORKDIR"
          rm -rf $WORKDIR
          ;;
        [Nn]) exit 0 ;;
    	*) red "无效的选择，请输入y或n" && menu ;;
    esac
}

restart_nezha() {
  reading "\n确定要重启吗？【y/n】: " choice
    case "$choice" in
       [Yy])
          run_nezha
          ;;
        [Nn]) exit 0 ;;
    	*) red "无效的选择，请输入y或n" && menu ;;
    esac
	
}

kill_nezha() {
reading "\n关闭nezha-dashboar进程，确定继续清理吗？【y/n】: " choice
  case "$choice" in
    [Yy]) kill -9 $(ps aux | grep '$WORKDIR/dashboard' | awk '{print $2}') ;;
       *) menu ;;
  esac
}

kill_all_tasks() {
reading "\n清理所有进程将退出ssh连接，确定继续清理吗？【y/n】: " choice
  case "$choice" in
    [Yy]) killall -9 -u $(whoami) ;;
       *) menu ;;
  esac
}


#主菜单
menu() {
    clear
    echo ""
    purple "=== AM科技 serv00 | nezha-dashboard哪吒面板 一键安装脚本 ===\n"
    purple "转载请著名出处，请勿滥用\n"
    echo -e "${green}AM科技 YouTube频道    ：${yellow}https://youtube.com/@AM_CLUB${re}"
    echo -e "${green}AM科技 GitHub仓库     ：${yellow}https://github.com/amclubs${re}"
    echo -e "${green}AM科技 个人博客       ：${yellow}https://am.809098.xyz${re}"
    echo -e "${green}AM科技 TG交流群组     ：${yellow}https://t.me/AM_CLUBS${re}"
    echo -e "${green}AM科技 脚本视频教程   ：${yellow}https://youtu.be/2B5yN09Wd_s${re}"
    echo   "======================="
    green  "1. 安装nezha-dashboard"
    echo   "======================="
    red    "2. 卸载nezha-dashboard"
    echo   "======================="
    green  "3. 重启nezha-dashboard"
    echo   "======================="
    green  "4. 查看配置信息"
    echo   "======================="
    yellow "5. 关闭nezha-dashboar进程"
    echo   "======================="
    yellow "6. 清理所有进程"
    echo   "======================="
    red    "7. serv00系统初始化"
    echo   "======================="
    red    "0. 退出脚本"
    echo   "======================="

    # 用户输入选择
    reading "请输入选择(0-5): " choice
    echo ""
    
    # 根据用户选择执行对应操作
    case "$choice" in
        1) install_nezha ;;
        2) uninstall_nezha ;;
        3) restart_nezha ;;
        4) cat $WORKDIR/data/config.yaml ;;
        5) kill_nezha ;;
        6) kill_all_tasks ;;
        7) system_initialize ;;
        0) exit 0 ;;
        *) red "无效的选项，请输入 0 到 5" ;;
    esac
}
menu
