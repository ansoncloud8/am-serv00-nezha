#!/bin/bash

USERNAME=$(whoami) && \
WORKDIR="/home/${USERNAME}/.nezha-dashboard"
CURRENT_VERSION="v0.0.0"
RELEASE_LATEST="v0.0.0"

get_current_version() {
    # echo "当前版本"
    # 如果VERSION文件不存在，设置CURRENT_VERSION为空
    if [ ! -f ${WORKDIR}/VERSION ]; then
        CURRENT_VERSION="v0.0.0"
        # echo "1当前版本：${CURRENT_VERSION}"
    else
        CURRENT_VERSION=$(cat ${WORKDIR}/VERSION)
        # echo "2当前版本：${CURRENT_VERSION}"
    fi
    echo "当前版本：${CURRENT_VERSION}"
}

get_latest_version() {
    # Get latest release version number
    RELEASE_LATEST=$(curl -s https://api.github.com/repos/ansoncloud8/am-nezha-freebsd/releases/latest | jq -r '.tag_name')
    if [[ -z "$RELEASE_LATEST" ]]; then
        echo "error: Failed to get the latest release version, please check your network."
        exit 1
    fi
    echo "最新版本：${RELEASE_LATEST}"
}

download_nezha() {
    if [ -z "$VERSION" ]; then
        # 如果没有传入VERSION变量，下载最新版本
        DOWNLOAD_LINK="https://github.com/ansoncloud8/am-nezha-freebsd/releases/latest/download/dashboard"
        VERSION=$RELEASE_LATEST  # 将版本设置为最新版本
    else
        # 如果传入了VERSION变量，下载指定版本
        DOWNLOAD_LINK="https://github.com/ansoncloud8/am-nezha-freebsd/releases/download/${VERSION}/dashboard"
    fi

    if ! wget -qO "$INSTALLER_FILE" "$DOWNLOAD_LINK"; then
        echo 'error: 下载失败，请检查网络或重试。'
        return 1
    fi
    echo "下载版本：${VERSION}"
	curl -s https://api.github.com/repos/ansoncloud8/am-nezha-freebsd/releases/latest | jq -r '.tag_name' > ${WORKDIR}/VERSION
    echo "${VERSION}" > "${WORKDIR}/VERSION"  # 将版本信息写入VERSION文件
    return 0
}


install_nezha() {
    install -m 755 ${TMP_DIRECTORY}/dashboard ${WORKDIR}/dashboard
}

generate_config(){
    echo "关于 Gitee Oauth2 应用：在 https://gitee.com/oauth/applications 创建，无需审核，Callback 填 http(s)://域名或IP/oauth2/callback"
    printf "请输入 OAuth2 提供商(github/gitlab/jihulab/gitee，默认 github): "
    read -r nz_oauth2_type
    printf "请输入 Oauth2 应用的 Client ID: "
    read -r nz_github_oauth_client_id
    printf "请输入 Oauth2 应用的 Client Secret: "
    read -r nz_github_oauth_client_secret
    printf "请输入 GitHub/Gitee 登录名作为管理员，多个以逗号隔开: "
    read -r nz_admin_logins
    printf "请输入站点标题: "
    read -r nz_site_title
    printf "请输入站点访问端口: "
    read -r nz_site_port
    printf "请输入用于 Agent 接入的 RPC 端口: "
    read -r nz_grpc_port

    if [ -z "$nz_admin_logins" ] || [ -z "$nz_github_oauth_client_id" ] || [ -z "$nz_github_oauth_client_secret" ] || [ -z "$nz_site_title" ] || [ -z "$nz_site_port" ] || [ -z "$nz_grpc_port" ]; then
        echo "error! 所有选项都不能为空"
        return 1
        rm -rf ${WORKDIR}
        exit
    fi

    if [ -z "$nz_oauth2_type" ]; then
        nz_oauth2_type=github
    fi
    wget -O ${WORKDIR}/data/config.yaml "https://raw.githubusercontent.com/naiba/nezha/master/script/config.yaml"

    sed -i '' "s/nz_oauth2_type/${nz_oauth2_type}/" ${WORKDIR}/data/config.yaml
    sed -i '' "s/nz_admin_logins/${nz_admin_logins}/" ${WORKDIR}/data/config.yaml
    sed -i '' "s/nz_grpc_port/${nz_grpc_port}/" ${WORKDIR}/data/config.yaml
    sed -i '' "s/nz_github_oauth_client_id/${nz_github_oauth_client_id}/" ${WORKDIR}/data/config.yaml
    sed -i '' "s/nz_github_oauth_client_secret/${nz_github_oauth_client_secret}/" ${WORKDIR}/data/config.yaml
    sed -i '' "s/nz_language/zh-CN/" ${WORKDIR}/data/config.yaml
    sed -i '' "s/nz_site_title/${nz_site_title}/" ${WORKDIR}/data/config.yaml
    sed -i '' "s/80/${nz_site_port}/" ${WORKDIR}/data/config.yaml

}

generate_run() {
    cat > ${WORKDIR}/start.sh << EOF
#!/bin/bash
pgrep -f 'dashboard' | xargs -r kill
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
    if pgrep -f "dashboard" > /dev/null; then
        echo "nezha-dashboard 已启动，请使用浏览器访问 http://${IP_ADDRESS}:${nz_site_port} 进行进一步配置。"
        echo "如果你配置了 Proxy 或者 Cloudflared Argo Tunnel，也可以使用域名访问 nezha-dashboard。"
        echo 
        echo "如果你想使用 pm2 管理 nezha-dashboard，请执行：pm2 start ~/.nezha-dashboard/start.sh --name nezha-dashboard"
    else
        rm -rf "${WORKDIR}"
        echo "nezha-dashboard启动失败，请检查端口开放情况，并保证参数填写正确，再重新安装！"
    fi
}


mkdir -p ${WORKDIR}/data
cd ${WORKDIR}
TMP_DIRECTORY="$(mktemp -d)"
INSTALLER_FILE="${TMP_DIRECTORY}/dashboard"

get_current_version
# echo "当前版本：${CURRENT_VERSION}"
get_latest_version
# echo "最新版本：${RELEASE_LATEST}"

[ ! -e ${WORKDIR}/data/config.yaml ] && generate_config
[ ! -e ${WORKDIR}/start.sh ] && generate_run

if [ -n "$VERSION" ] || [ "${RELEASE_LATEST}" != "${CURRENT_VERSION}" ]; then
    download_nezha
    EXIT_CODE=$?
    if [ ${EXIT_CODE} -eq 0 ]; then
        :
    else
        rm -r "$TMP_DIRECTORY"
        run_nezha
        exit
    fi
    install_nezha
    rm -rf "$TMP_DIRECTORY"
    run_nezha
    exit
fi
run_nezha
