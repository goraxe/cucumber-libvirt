# This file licensed under the GPL v 2.0 and above where appropriate

# define the type of server that we want to build
Given /^that I have vm config file "([^"]*)"$/ do |config|
  # set a global to be used in the rest of the process

  @vm_config = YAML::load(File.open(config)) 

  # build up a picture of how the network should look
  # use some global vars to keep track
  @net = nil
  @ips = {}
  @vm_config.each |vm, config| do
      # FIXME: only support ipv4 currently
      # FIXME: assume class C, cidr/24
      ip = config['ip']
      ip =~ /(\d+.\d+\.\d+)\.(\d+)/
      net = "#{$1}.1"
      host_ip = $2
      if host_ip.to_i == 1 then
          raise "#{ip} is reserved for the host"
      elsif not @ips[ip].nil? then
          raise "#{ip} has already been assigned"
      else
          @ips[ip] =vm
      end
      if @net.nil? then
          @net = net
      elsif @net != net then
          raise "all machines must be on the same network!"
      end
      config['mac'] = generate_mac(host_ip)
  end
#define the network xml
  hosts = @vm_config.map |vm, config| do
      return "<host mac='#{config['mac']}' name='#{config['name']}' ip='#{config['ip']}' />"
  end.join"\n"
  network_xml <<eos
<network>
  <name>cucumber-libvirt</name>
  <bridge name='vircuke1' />
  <forward mode='nat' />
  <ip address="#{@net}" netmask="255.255.255.0">
    <dhcp>
    #{hosts}
    </dhcp>
  </ip>
</network>
eos

net = @vmconn.define_network_xml(network_xml)

@net.create
end

def generate_mac(ip)
    mac = '52:54:00:ff:ff' + ( 255 - ip).to_s(16)
    return mac
end

# create the XML file to be used by LibVirt to import and create/edit/delete the VM
Then /^I create the vm "([^"]*)"$/ do |vm|
    create_vm(@vm_config[vm])
  # set some variables to be used in the file
#  virt_mem = @xml_description['virt_ram'].to_i  # the memory that is allocated in cobbler (KB)
#  virt_ram = virt_mem.to_i * 1024 # the memory to be used (MB)
#  mac = @xml_description['interfaces']['eth0']['mac_address']  # The mac address to be assigned - Cobbler won't build without this!
#  virt_bridge = @xml_description['interfaces']['eth0']['virt_bridge']  # The bridge interface on the physical host to used as defined in cobbler - loads of stuff breaks if this isn't set properly!

end

def create_vm(config)
  # Generate the XML output as defined by LibVirt at http://www.libvirt.org/format.html

#    <interface type='bridge'>
#      <mac address='#{config['mac']}'/>
#      <source bridge='#{virt_bridge}'/>
#      <model type='virtio' />
#    </interface>
  # The system definition
  @sys_xmloutput = <<-eos
<domain type='kvm'>
  <name>#{config['name']}</name>
  <uuid></uuid>
  <memory>#{config['ram']}</memory>
  <currentMemory>#{config['ram']}</currentMemory>
  <vcpu>#{config['cpus']}</vcpu>
  <os>
    <type arch='#{config['arch']}' machine='pc'>hvm</type>
    <boot dev='hd' />
    <boot dev='network' />
  </os>
  <features>
    <acpi/>
    <apic/>
    <pae/>
  </features>
  <clock offset='utc'/>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>restart</on_crash>
  <devices>
    <emulator>/usr/bin/kvm</emulator>
    <disk type='file' device='disk'>
      <source file='#{config['disk']}'/>
      <target dev='hda' bus='ide'/>
    </disk>
    <input type='mouse' bus='ps2'/>
    <graphics type='vnc' port='-1' autoport='yes' keymap='en-gb'/>
    <video>
      <model type='cirrus' vram='9216' heads='1'/>
    </video>
  </devices>
</domain>
eos

  # make sure its undefined
  domain = @vmconn.lookup_domain_by_name(config['name'])
  domain.undefine
  # Now define the VM
  @vmconn.define_domain_xml(@sys_xmloutput)
  # query libvirt for the domain we just created
  domain = @vmconn.lookup_domain_by_name(config['name'])
  # and create and start the VM
  domain.create()

end


# sometimes we just need to know that the VM has been created...

# which server type are we looking at here?
Given /^that I want to confirm the server "([^"]*)" has been provisioned$/ do |serverType|
	# set the global to the value passed
	@serverType = serverType
end

# find out what we should be checking for
Then /^I should check the status of the server$/ do
  # retrieve the serverType info from cobbler
  @xml_description = @cblr_api.call("get_system_for_koan",@serverType)
  # get the hostname
  serverName = @xml_description['hostname']
  # Connect to libvirt and create a domain object based upon the "ci-build" hostname
  @ciDomain = @vmconn.lookup_domain_by_name(serverName.to_s  + "-ci-build")
end

# So we know the VM exists - is it running or stopped?
Then /^the server should have a status of "([^"]*)"$/ do |requestedStatus|
  # get the current status of the domain
  curState = @ciDomain.info.state
  
  # Unfortunately the status is only ever returned as an int - any one who wants to find a prettier way of achieving the following is more than welcome to try!

  # The requested status is passed as a str, we need to convert it into an int so we can compare it with the current value returned
  case requestedStatus
	when "running" then reqState = 1
	when "stopped" then reqState = 5
  end

  # The current state is returned as an int so we need to convert it into a str so we can generate useful error messages
  case curState
	when 1 then actualStatus = "running"
	when 5 then actualStatus = "stopped"
	else actualStatus = "Unknown"
  end

  # check to see if the int values match - if they don't, error and print the string values... Simples!
  raise ArgumentError, "The VM was requested to be #{requestedStatus} however it was found to be #{actualStatus}" unless reqState == curState
  
end


# I really need to get around to writing these tests!
Then /^I should ping the server$/ do
	# Set a counter so this script can bail if the build takes too long/fails to ping
	counter = 0
	# ping the value of the IP Address retrieved from the xml_description
	while Ping.pingecho(@xml_description['interfaces']['eth0']['ip_address'])  == false do
		sleep(10)
		counter = counter +1
		puts "Counter currently at: #{counter}"
		raise ArgumentError, "It's taken over five minutes to try and ping this system, I'm bailing out now!" unless counter < 30
	end
	puts "I can ping the host! :)"
end

Then /^I should be able to connect the server on port "([^"]*)"$/ do |port|
	# Make sure the port checker doesn't time out
	ccounter = 0
	while is_port_open(@xml_description['interfaces']['eth0']['ip_address'],port) == false do
		sleep(10)
		ccounter = ccounter + 1
		puts "Connection Counter currently at #{ccounter}"
		raise ArgumentError "No connection to port #{port} on this server after five minutes, bailing out now..." unless ccounter < 30
	end
end

# All the tests that we wanted to run are now complete, let's throw away the server so we know that we are always starting from a clean system next time.

# Which server do we want to destroy?
Given /^that I want to destroy the server "([^\"]*)"$/ do |serverType|
	# set the server type as before
	@serverType = serverType
end


# Destroy (which confusingly doesn't delete!) the server
Then /^I should destroy the server$/ do
	# we still have the domain set from earlier in the process, so stop it from running and destroy it
	@ciDomain.destroy()
end

# Remove the storage
Then /^I should destroy the associated storage$/ do
	# get the path to the storage as defined by cobbler
	path = @xml_description['virt_path'] + "/" + @xml_description['hostname'] + "-ci-build.img"
	# echo a debug message
	puts "Trying to delete #{path}"
	# get the volume details and assign it to an object	
	volume = @vm_stor.lookup_volume_by_path("#{@xml_description['virt_path'] + "/" + @xml_description['hostname']}-ci-build.img")
	# delete the object (unlike pools and domains, you don't have to undefine volumes as far as I can tell - I tried and it wouldn't let me!)
	volume.delete()	
end


# we're done here, let's throw away the VM
Then /^I should undefine the server$/ do
	# Use the existing domain pointer and undefine it, we're finished and all traces have disappeared from our systems!
	@ciDomain.undefine()
	
end

