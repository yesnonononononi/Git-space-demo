$shutdownChoice = Read-Host "是否关机?[y/n]"

if ($shutdownChoice -ieq "y") {
    Write-Host "在60秒后即将关机,请保存重要文件"
    shutdown /s /t 60

    $choice_interrupt = Read-Host "输入 y 停止" 

    if ($choice_interrupt -ieq "y") {
        Write-Host "已经停止!"
        shutdown /a
    }
    
    Read-Host "按任意键退出..."
} else {
    Read-Host "按任意键退出..."
    exit
}