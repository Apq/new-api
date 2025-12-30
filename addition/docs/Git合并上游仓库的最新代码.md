## 克隆仓库后指定上游仓库

- 命令行方式

  ```bash
  # 只需要指定一次,也可以在TortoiseGit界面上添加远端:名称填 upstream, URL填 上游仓库地址
  git remote add upstream https://github.com/原作者/公开仓库.git
  ```
- TortoiseGit可视化操作
  使用TortoiseGit克隆仓库完成后,如果发现没有自动签出文件，则需要手动签出需要进行二次开发的分支。

以下这个警告就是没自动签出文件，需要手动签出。
![](../img/Pasted%20image%2020251213162727.png)
![](../img/Pasted%20image%2020251213162854.png)

添加上游仓库

![](../img/Pasted%20image%2020251213162043.png)
![](../img/Pasted%20image%2020251213163016.png)

## 合并上游的最新代码

- 方法一、命令行操作

  ```bash
  # 获取上游最新代码
  git fetch upstream
  # 合并上游更新到本地
  git merge upstream/main
  ```
- 方法二、TortoiseGit可视化操作
  ![](../img/Pasted%20image%2020251214124849.png)
  ![](../img/Pasted%20image%2020251214124912.png)
  ![](../img/Pasted%20image%2020251214124935.png)
  合并选项默认即可，啥都不用勾
  ![](../img/Pasted%20image%2020251214125000.png)
