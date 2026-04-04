import paramiko
import sys

host = "5.78.207.11"
user = "root"
password = "e@gFV5B3N85qO30m%byTRG8Nhb1&57aO6@&ZcFqi"

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(host, username=user, password=password, timeout=30)

stdin, stdout, stderr = ssh.exec_command(
    "systemctl restart eraonline-server && sleep 2 && systemctl is-active eraonline-server && journalctl -u eraonline-server -n 20 --no-pager 2>&1 | cat"
)
out = stdout.read().decode('utf-8', errors='replace')
sys.stdout.buffer.write(out.encode('utf-8'))
ssh.close()
