# frozen_string_literal: true

module Spdk
  def self.user
    "spdk"
  end

  def self.home
    File.join("", "home", user)
  end

  def self.vhost_dir
    File.join("", "var", "storage", "vhost")
  end

  def self.vhost_sock(vm_name)
    File.join(vhost_dir, vm_name)
  end

  def self.hugepages_dir
    File.join(home, "hugepages")
  end

  def self.rpc_sock
    File.join(home, "spdk.sock")
  end

  def self.install_prefix
    File.join("", "opt")
  end

  def self.rpc_py
    bin = File.join(install_prefix, "spdk", "scripts", "rpc.py")
    "#{bin} -s #{rpc_sock}"
  end
end