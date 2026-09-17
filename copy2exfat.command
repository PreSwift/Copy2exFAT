#!/usr/bin/osascript

on run
    try
        -- 选择操作类型
        set operation to choose from list {"选择文件", "选择文件夹"} with prompt "请选择要拷贝的类型："
        if operation is false then return
        set operation to item 1 of operation
        
        -- 根据选择类型显示相应的对话框
        if operation is "选择文件" then
            set sourceItems to choose file with prompt "请选择要拷贝的文件：" with multiple selections allowed
        else
            set sourceItems to {choose folder with prompt "请选择要拷贝的文件夹："}
        end if
        
        -- 构建源路径字符串
        set sourceStr to ""
        repeat with f in sourceItems
            set sourceStr to sourceStr & quoted form of POSIX path of f & " "
        end repeat

        -- 选择目标位置（exFAT磁盘）
        set targetFolder to choose folder with prompt "请选择 exFAT 磁盘目标文件夹："
        set targetPosix to POSIX path of targetFolder

        display notification "开始拷贝到 exFAT 磁盘…" with title "拷贝工具"
        log "目标路径：" & targetPosix

        -- 执行拷贝 + 同步缓存（关键：防止exFAT损坏）
        if operation is "选择文件夹" then
            -- 获取源文件夹路径
            set sourceFolder to item 1 of sourceItems
            set sourcePath to POSIX path of sourceFolder
            -- 获取源文件夹名称
            set sourceName to do shell script "basename " & quoted form of sourcePath
            -- 构建目标文件夹路径
            set targetPath to targetPosix & sourceName
            -- 创建目标文件夹并复制内容
            set cmd to "mkdir -p " & quoted form of targetPath & " && cp -R " & quoted form of sourcePath & "/. " & quoted form of targetPath & " && sync"
        else
            -- 对于文件，使用原来的命令
            set cmd to "cp -f " & sourceStr & " " & quoted form of targetPosix & " && sync"
        end if
        do shell script cmd

        -- 完成提示
        display dialog "✅ 拷贝完成！已同步磁盘缓存，可安全弹出。" buttons {"确定"} default button 1 with title "成功"
        display notification "拷贝完成" sound name "default"

    on error errMsg
        display dialog "❌ 失败：" & errMsg buttons {"取消"} with icon stop with title "拷贝错误"
    end try
    tell application "Terminal" to close front window
end run