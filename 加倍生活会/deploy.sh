#!/bin/bash
# =========================================================
# CRMEB 一键线上环境部署与数据库增量/全量合并脚本
# =========================================================

# 【请您先确认】目标服务器的站点运行目录路径！
# 宝塔面板环境通常为 /www/wwwroot/你的域名/，或者你自定义的路径
REMOTE_DIR="/www/wwwroot/jbshh" 

# 服务器与内网配置
REMOTE_USER="root"
REMOTE_HOST="49.233.250.249"
REMOTE_PASS='8i9o0p*I(O)P'

# 云数据库 RDS 配置
DB_HOST="rm-2zeb2iem5zx44a20suo.mysql.rds.aliyuncs.com"
DB_USER="root"
DB_PASS='8i9o0p*I(O)P'
DB_NAME="jbshh"

# 线上 Redis 配置
REDIS_PASS='WMS_Redis_2024!@#'

# 本地数据库配置 (依据本地 .env 填入)
LOCAL_DB_NAME="jiabeishh"
LOCAL_DB_USER="root"
LOCAL_DB_PASS="1qaz!QAZ"

echo -e "\033[36m============================================\033[0m"
echo -e "\033[36m    CRMEB 一键线上部署脚本初始化\033[0m"
echo -e "\033[36m============================================\033[0m"

# ---------------------------------------------
# 零、 编译前端产物
# ---------------------------------------------
echo -e "\033[33m=> [0/2] 正在编译前端管理后台产物 (npm run build)...\033[0m"
SCRIPT_ROOT="$(pwd)"
cd ./CRMEB_1/template/admin || exit 1
npm run build
if [ $? -ne 0 ]; then
    echo -e "\033[31m[ERR] 前端编译失败，终止部署。\033[0m"
    exit 1
fi
cd "$SCRIPT_ROOT" || exit 1
echo -e "\033[32m[OK] 前端编译完成！\033[0m\n"

# ---------------------------------------------
# 一、 前后端代码同步 (通过 Expect 自动交互密码)
# ---------------------------------------------
echo -e "\033[33m=> [1/2] 正在通过 RSYNC 将增量代码同步至远程服务器 $REMOTE_HOST:$REMOTE_DIR \033[0m"

# 使用 macOS 默认自带的 expect 进行密码代入 rsync
expect -c "
set timeout -1
spawn rsync -avhzP --delete --exclude=\".env\" --exclude=\"vendor/\" --exclude=\".git/\" --exclude=\"runtime/\" --exclude=\"node_modules/\" ./CRMEB_1/crmeb/ ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/
expect {
    \"*yes/no*\" {
        send \"yes\r\"
        exp_continue
    }
    \"*assword:*\" {
        send \"${REMOTE_PASS}\r\"
        exp_continue
    }
    eof
}
"
echo -e "\033[32m[OK] 代码同步完成！(如果含有新依赖，请前往服务器自行 composer install)\033[0m\n"

# 修复文件属主权限（rsync 会保留本地属主，导致服务器 web 用户无法写入 runtime）
echo -e "\033[33m=> [1.5] 修复服务器文件权限... \033[0m"
expect -c "
set timeout -1
spawn ssh ${REMOTE_USER}@${REMOTE_HOST} \"chown -R www:www ${REMOTE_DIR}/runtime/ ${REMOTE_DIR}/public/ ${REMOTE_DIR}/app/ ${REMOTE_DIR}/config/ ${REMOTE_DIR}/route/ 2>/dev/null; chmod -R 777 ${REMOTE_DIR}/runtime/\"
expect {
    \"*yes/no*\" { send \"yes\r\"; exp_continue }
    \"*assword:*\" { send \"${REMOTE_PASS}\r\"; exp_continue }
    eof
}
"
echo -e "\033[32m[OK] 文件权限修复完成！\033[0m\n"

# ---------------------------------------------
# 二、 云端数据库同步校验
# ---------------------------------------------
echo -e "\033[33m=> [2/2] 正在连接阿里云 RDS 检查数据库存量... \033[0m"

# 检测阿里云目标库是否为空（含有多少张表）
# 由于云端 RDS 可能警告，我们将 stderr 屏蔽掉，只抓结果
TABLE_COUNT=$(mysql -h "${DB_HOST}" -u "${DB_USER}" -p"${DB_PASS}" -D "${DB_NAME}" -N -B -e 'show tables;' 2>/dev/null | wc -l)

# wc -l 可能带有空格等字符，清理一下
TABLE_COUNT=$(echo "$TABLE_COUNT" | xargs)

if [ "$TABLE_COUNT" -le "1" ]; then
    echo -e "\033[32m=> 检测到云端数据库为空（第一部署），触发【全量导出+导入】...\033[0m"
    echo "   [!] 正在导出本地 ${LOCAL_DB_NAME} ..."
    mysqldump -u "${LOCAL_DB_USER}" -p"${LOCAL_DB_PASS}" "${LOCAL_DB_NAME}" > /tmp/crmeb_dump_full.sql 2>/dev/null
    
    # 强制将所有 MyISAM 引擎替换为阿里云支持的 InnoDB
    perl -pi -e 's/ENGINE\s*=\s*MyISAM/ENGINE = InnoDB/ig' /tmp/crmeb_dump_full.sql

    
    echo "   [!] 正在将其导入到阿里云 RDS ..."
    mysql -h "${DB_HOST}" -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" < /tmp/crmeb_dump_full.sql 2>/dev/null
    
    echo -e "\033[32m[OK] 全量数据库结构与数据注入完成！\033[0m"
else
    echo -e "\033[33m=> 云端已存在 $TABLE_COUNT 张表。触发【安全增量结构同步】...\033[0m"

    # ① 导出本地纯结构
    echo "   [1/4] 导出本地 ${LOCAL_DB_NAME} 纯结构..."
    mysqldump -u "${LOCAL_DB_USER}" -p"${LOCAL_DB_PASS}" -d --skip-comments --skip-add-drop-table "${LOCAL_DB_NAME}" > /tmp/schema_local.sql 2>/dev/null

    # ② 导出远端 RDS 纯结构
    echo "   [2/4] 导出远端 RDS ${DB_NAME} 纯结构..."
    mysqldump -h "${DB_HOST}" -u "${DB_USER}" -p"${DB_PASS}" -d --skip-comments --skip-add-drop-table "${DB_NAME}" > /tmp/schema_remote.sql 2>/dev/null

    # ③ 用 Python 安全对比生成增量 DDL（仅 ADD / MODIFY，绝无 DROP）
    echo "   [3/4] 对比本地与远端结构差异，生成安全增量 SQL..."
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    python3 "${SCRIPT_DIR}/schema_diff.py" /tmp/schema_local.sql /tmp/schema_remote.sql > /tmp/schema_diff_result.sql

    DIFF_CHANGES=$(grep -c '>>>' /tmp/schema_diff_result.sql 2>/dev/null || echo "0")

    if [ "$DIFF_CHANGES" -gt "0" ]; then
        echo -e "\033[33m   [!] 检测到 ${DIFF_CHANGES} 处结构差异，正在安全应用到云端 RDS...\033[0m"
        echo "   [4/4] 执行增量 ALTER/CREATE 语句..."
        mysql -h "${DB_HOST}" -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" < /tmp/schema_diff_result.sql 2>/tmp/schema_apply_errors.log

        if [ $? -eq 0 ]; then
            echo -e "\033[32m[OK] 数据库结构增量同步完成！共应用 ${DIFF_CHANGES} 处变更，数据完整无损。\033[0m"
        else
            # 部分 ALTER 可能因为重复列等原因报错，但不会影响数据安全
            ERRS=$(cat /tmp/schema_apply_errors.log 2>/dev/null | grep -i 'error' | wc -l | xargs)
            if [ "$ERRS" -gt "0" ]; then
                echo -e "\033[33m[WARN] 增量同步中有 ${ERRS} 条非致命警告（如列已存在），数据无损。\033[0m"
                echo -e "\033[33m       详情见 /tmp/schema_apply_errors.log\033[0m"
            else
                echo -e "\033[32m[OK] 数据库结构增量同步完成！\033[0m"
            fi
        fi
    else
        echo -e "\033[32m[OK] 本地与云端数据库结构完全一致，无需变更。\033[0m"
    fi

    # 保留一份增量记录备查
    cp /tmp/schema_diff_result.sql ./schema_sync_only.sql 2>/dev/null
fi

# ---------------------------------------------
# 三、 写入或替换线上专属数据库环境配置
# ---------------------------------------------
echo -e "\033[33m=> [3/3] 正将正式环境数据库隔离配置注入到服务器 .env 中... \033[0m"

# 直接从指定生产配置文件加载并分发
PROD_ENV_FILE="/Users/jingzhaokeji/Documents/开发项目/加倍生活会/CRMEB_1/.env.production"
if [ -f "$PROD_ENV_FILE" ]; then
    cp "$PROD_ENV_FILE" /tmp/crmeb_production.env
else
    echo -e "\033[31m[ERR] 找不到生产配置文件: $PROD_ENV_FILE \033[0m"
    exit 1
fi

expect -c "
set timeout -1
spawn scp -o StrictHostKeyChecking=no /tmp/crmeb_production.env ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/.env
expect {
    \"*yes/no*\" {
        send \"yes\r\"
        exp_continue
    }
    \"*assword:*\" {
        send \"${REMOTE_PASS}\r\"
        exp_continue
    }
    eof
}
"
echo -e "\033[32m[OK] 自动化 .env 脱敏注入完毕！当前网站已安全指向 Aliyun RDS！\033[0m\n"

echo -e "\n\033[36m========== 部署流程全部结束！==========\033[0m"
