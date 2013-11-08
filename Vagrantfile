# -*- mode: ruby -*-
# vi: set ft=ruby :

# Author: Tuomo Tanskanen <tumi@tumi.fi>

Vagrant.configure("2") do |config|
  config.vm.define :trac do |trac|
    trac.vm.box = "precise64"
    trac.vm.box_url = "http://files.vagrantup.com/precise64.box"

    trac.vm.network :forwarded_port, guest: 80, host: 30080
    trac.vm.network :forwarded_port, guest: 443, host: 30443

    trac.vm.provision :shell, :path => "provision.sh"
  end

  config.vm.provider "vmware_fusion" do |v, override|
    override.vm.box = "precise64_fusion"
    override.vm.box_url = "http://files.vagrantup.com/precise64_vmware.box"
  end
end
