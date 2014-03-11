# -*- mode: ruby -*-
# vi: set ft=ruby :

# Author: Tuomo Tanskanen <tumi@tumi.fi>

Vagrant.configure("2") do |config|
  config.vm.define :trac do |config|
    # Vagrant 1.5 type box naming
    config.vm.box = "hashicorp/precise64"

    config.vm.network :forwarded_port, guest: 80, host: 30080
    config.vm.network :forwarded_port, guest: 443, host: 30443

    config.vm.provision :shell, :path => "provision.sh"
  end
end
