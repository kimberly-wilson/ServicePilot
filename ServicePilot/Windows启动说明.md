# Windows 启动说明

启动顺序依据项目的[完整使用指南](完整使用指南.md)。使用 Docker Compose 时，Python 3.12 和 requirements.txt 中的依赖在镜像内安装，无需使用项目中从 macOS 复制过来的 `.venv`。

## 首次准备

1. 安装 WSL 2 并启用 VirtualMachinePlatform。如果 Windows 提示需要重启，先保存工作并重启。
2. 安装并启动 Docker Desktop，使用 WSL 2 后端，等待 Docker Engine 就绪。
3. 编辑本机 `.env`，填写有效的 `ANTHROPIC_API_KEY`，确认 `ANTHROPIC_BASE_URL` 和 `ANTHROPIC_MODEL` 对应你的服务商。不要将密钥提交到版本库。

## 分步启动

在项目目录打开 PowerShell：

```powershell
.\start-windows.ps1
```

该脚本依次校验配置、启动 Redis/ChromaDB、构建并启动 EchoMind、启动 Prometheus/Nginx，最后检查 HTTP 接口。首次构建需要下载容器镜像、Python 依赖和向量模型，耗时取决于网络速度。任一步失败会停止，修复后可以重新执行。

如果 PowerShell 的当前执行策略禁止运行脚本，可以仅为本次进程使用：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\start-windows.ps1
```

需要额外发送一条真实模型对话时：

```powershell
.\start-windows.ps1 -TestChat
```

也可以按教程逐条运行：

```powershell
docker compose config --quiet
docker compose up -d --wait redis chromadb
docker compose up -d --build --wait --wait-timeout 300 echomind
docker compose up -d --wait prometheus nginx
docker compose ps
Invoke-RestMethod http://localhost:8000/health
```

## 访问与排障

- Swagger：[http://localhost:8000/docs](http://localhost:8000/docs)
- Nginx 入口：[http://localhost/docs](http://localhost/docs)
- Prometheus：[http://localhost:9090](http://localhost:9090)
- 查看日志：`docker compose logs --tail 100 echomind`
- 停止服务并保留数据：`docker compose stop`

`/health` 成功仅说明应用就绪；模型密钥是否有效还需通过 `/chat` 验证。若日志出现 `401`，检查 `.env` 中的密钥，并执行 `docker compose up -d --force-recreate echomind` 使更新后的环境变量生效。

首次配置记录：2026-09-18 已安装 WSL 2.7.13，启用 VirtualMachinePlatform 后系统返回 `RestartNeeded: True`；当时 `.env` 的模型连通性检查返回 401。容器启动与业务验证需在重启并修正密钥后继续。

后续排障记录：重启后直接打开 Docker Desktop 出现安装注册表路径错误，执行官方组件注册工具并通过 `docker desktop start` 已能启动界面和后端进程。桌面及开始菜单快捷方式已改用 `docker desktop start --detach`。引擎仍报告虚拟机平台不可用；系统功能查询显示 VirtualMachinePlatform 已启用，但计算/网络服务缺失。已补启用 Microsoft-Windows-Subsystem-Linux 并重新核对 VirtualMachinePlatform，Windows 再次返回 `RestartNeeded: True`。需再次重启后核验引擎，尚未启动项目容器。

再次重启后的检查：两个功能均显示 Enabled，但 `vmcompute`、`hns` 服务仍缺失；`C:\Windows\WinSxS\pending.xml` 中仍有部署 `vmcompute.exe` 的挂起事务。DISM ScanHealth 检出 1508 项组件文件损坏，结论为可修复；SFC verifyonly 因挂起修复无法执行。已启动 `DISM /Online /Cleanup-Image /RestoreHealth /NoRestart`，结果日志位于 `%TEMP%\EchoMind-setup\component-restore.log`。应先确认修复结果，再继续启动 Docker，不能将功能显示 Enabled 当作引擎已就绪。

Docker 的 `sailor-ingest.sock` 和 `engine.sock` 遗留文件曾导致启动报错。已在停止 Docker 后将 `%LOCALAPPDATA%\Docker\run` 和仅含 socket 的 `%LOCALAPPDATA%\docker-secrets-engine` 目录改名保留（后缀 `-stale-日期时间`），重建空目录后启动已越过该错误。未恢复出厂设置，未清空镜像、数据卷或项目数据。

系统修复结果：2026-09-18 23:59，DISM RestoreHealth 返回退出码 0，提示“还原操作已成功完成”。CBS 摘要确认修复 1508 项文件损坏和 2075 项文件标志问题，共 3583 项。原先缺失的 `vmcompute.exe` 已恢复到 WinSxS 组件存储，但尚未部署到 System32，虚拟化服务仍不存在，相关安装操作仍在 pending.xml 中。需保存工作并重启 Windows 完成挂起的组件安装，再检查 `Get-Service vmcompute,hns` 和 `docker version`。不能据此宣称 Docker 引擎或项目已经启动。修复日志保存在 `logs/windows-setup/`。

2026-09-19 00:12：重启后 `VirtualMachinePlatform` 与 WSL 功能显示 Enabled，但 `vmcompute`/`hns` 仍未部署，系统同时保留 CBS 与 Windows Update 的 RebootPending 标志。进一步启用 `HypervisorPlatform` 并执行 `bcdedit /set hypervisorlaunchtype auto`；DISM 成功完成并返回 `3010`（成功，需要重启）。下一次重启后应先验证 `vmcompute`、`hns`、`wsl --status` 与 Docker Server，再启动项目。

2026-09-19 00:18：切换 Docker Desktop 4.91 到 Docker VMM（备份安装设置后设 `wslEngineEnabled=false`、`useLibkrun=true`）。VMM 的 `linux/sailor` 虚拟机可启动并进入 running，但主机到虚拟机的 virtio-vsock 通道持续返回 Windows 错误 10022，Docker daemon 未就绪。SFC 仍被陈旧的 pending 修复事务阻止。Windows Update 检查没有待安装更新，因此停止 Docker，并通过 DISM 禁用损坏的 `VirtualMachinePlatform` 和 WSL 功能以清理事务；两项均成功返回 `3010`。保留已启用的 `HypervisorPlatform`，重启后优先验证 Docker VMM；若 VMM 正常，则无需重新启用 WSL。

## 最终验证结果（2026-09-19）

Windows 组件存储经 DISM 修复后，共修复 1154 项损坏；KB5129195 已完成提交，系统版本为 26200.9457，CBS 和 Windows Update 均无 RebootPending。`vmcompute`、HNS、WSL Service 与 Hyper-V 管理程序已恢复正常。

Docker Desktop 4.69.0（Docker Server 29.4.0）已一次启动成功。EchoMind、Redis、ChromaDB、Prometheus、Nginx 五个容器均已通过健康检查；`/health`、`/knowledge/stats`、`/skills`、Swagger 和 Prometheus 均返回 HTTP 200，Prometheus 的 `echomind-app` 抓取目标为 up。

以后正常启动无需再次启用 Windows 功能或重启系统：先启动 Docker Desktop，待 `docker version` 能显示 Server 后，在项目目录运行 `powershell -NoProfile -ExecutionPolicy Bypass -File .\start-windows.ps1`。如果仅修改 `.env`，执行 `docker compose up -d --force-recreate echomind` 使环境变量生效。

当前 `.env` 中的模型服务密钥此前验证返回 401；基础服务不受影响，但调用 `/chat` 前需要填入有效密钥。