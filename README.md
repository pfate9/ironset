# ironset

一键修改 macOS 文件类型默认打开方式，并强制刷新图标和 Finder。

## 依赖

- [duti](https://github.com/moretension/duti) — `brew install duti`
- macOS（依赖 `mdfind`、`mdls`、`lsregister` 等系统工具）

## 安装

```bash
# 克隆仓库
git clone https://gitee.com/fateg9/ironset.git

# 加到 PATH（可选）
ln -s "$(pwd)/ironset.sh" /usr/local/bin/ironset
```

## 用法

```bash
ironset <扩展名> <应用名>
```

示例：

```bash
# 用 Typora 打开 .md 文件
ironset md Typora

# 也可以带点号
ironset .md Typora

# 用 VS Code 打开 .py 文件（带空格的应用名加引号）
ironset py 'Visual Studio Code'

# 用 Firefox 打开 .html 文件
ironset html Firefox
```

## 原理

`ironset` 做了 7 步操作来确保文件关联彻底生效：

1. 停止图标服务和 Dock（防止缓存干扰）
2. 用 `duti` 绑定扩展名到应用
3. 强制扫描应用包注册到 Launch Services
4. 更新时间戳后再次注册（防止被 `lsregister` 因时间戳太旧跳过）
5. 重置并重建 Launch Services 数据库
6. 清理图标磁盘缓存
7. 重启 Finder

## License

MIT
