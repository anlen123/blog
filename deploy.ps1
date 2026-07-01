# Hexo 博客一键部署脚本
# 用法: .\deploy.ps1 "提交信息"
# 示例: .\deploy.ps1 "新增文章：xxx"

param(
    [string]$Message = "update: 博客内容更新"
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# ========== 1. 确保在 main 分支 ==========
Write-Host ">>> 检查分支..." -ForegroundColor Cyan
$currentBranch = git rev-parse --abbrev-ref HEAD
if ($currentBranch -ne "main") {
    Write-Host "当前在 $currentBranch，切换到 main..." -ForegroundColor Yellow
    git checkout main
}
Write-Host "当前分支: main" -ForegroundColor Green

# ========== 2. 设置代理 ==========
Write-Host ">>> 配置代理..." -ForegroundColor Cyan
git config http.proxy http://127.0.0.1:7892
git config https.proxy http://127.0.0.1:7892

# ========== 3. Hexo 清理、生成、部署 ==========
Write-Host ">>> Hexo 清理..." -ForegroundColor Cyan
npx hexo clean

Write-Host ">>> Hexo 生成..." -ForegroundColor Cyan
npx hexo generate

Write-Host ">>> Hexo 部署..." -ForegroundColor Cyan
npx hexo deploy

# ========== 4. 提交源码到 main 分支 ==========
Write-Host ">>> 提交源码..." -ForegroundColor Cyan
git add .
$hasChanges = git status --porcelain
if ($hasChanges) {
    git commit -m $Message
    git push origin main
    Write-Host ">>> 源码已推送到 main 分支" -ForegroundColor Green
} else {
    Write-Host ">>> 无需提交，源码无变更" -ForegroundColor Yellow
}

# ========== 5. 清理代理设置 ==========
git config --unset http.proxy
git config --unset https.proxy

Write-Host "========================================" -ForegroundColor Green
Write-Host "部署完成！" -ForegroundColor Green
Write-Host "站点: https://anlen123.github.io/blog/" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
