# This file licensed under the GPL v 2.0 and above where appropriate

# define the type of server that we want to build
Given /^that I have vm config file "([^"]*)"$/ do |config|
  # set a global to be used in the rest of the process
  @vm_config = YAML::load(File.open(config)) 
  @domains =  {} 

  # build up a picture of how the network should look
  # use some global vars to keep track
  @net = nil
  @ips = {}
  @vm_config.each do |vm,config| 
      ['name','ram', 'cpus', 'arch', 'disk'].each do |field|
          if config['name'].nil? then
              raise "#{field} must be supplied in vm config"
          end
      end
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
  hosts = @vm_config.map do |vm, config|
      "<host mac='#{config['mac']}' name='#{config['name']}' ip='#{config['ip']}' />"
  end.join"\n"
  network_xml = <<eos
<network>
  <name>cucumber-libvirt</name>
  <forward mode='nat' />
  <ip address="#{@net}" netmask="255.255.255.0">
    <dhcp>
    #{hosts}
    </dhcp>
  </ip>
</network>
eos
    begin
        net =  @vmconn.lookup_network_by_name('cucumber-libvirt')
        if not net.nil? then
            net.destroy
            net.undefine
        end
    rescue
    end
    begin
        net = @vmconn.define_network_xml(network_xml)

        net.create
    rescue Libvirt::DefinitionError => e
        puts "failed to define network: " +  e.libvirt_message
        raise
    end
end

def generate_mac(ip)
    normalised_ip = 255 - ip.to_i
    mac = '52:54:00:ff:ff:' + normalised_ip.to_s(16)
    return mac
end

# create the XML file to be used by LibVirt to import and create/edit/delete the VM
Then /^I create the vm "([^"]*)"$/ do |vm|
    create_vm(@vm_config[vm])
end

def create_vm(config)
  # Generate the XML output as defined by LibVirt at http://www.libvirt.org/format.html

  # The system definition
  @sys_xmloutput = <<-eos
<domain type='kvm'>
  <name>#{config['name']}</name>
  <uuid></uuid>
  <memory>#{config['ram'] * 1024}</memory>
  <currentMemory>#{config['ram'] *1024}</currentMemory>
  <vcpu>#{config['cpus']}</vcpu>
  <os>
    <type arch='#{config['arch']}' machine='pc'>hvm</type>
    <boot dev='hd' />
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
    <interface type='network'>
        <mac address='#{config['mac']}' />
        <source network='cucumber-libvirt' />
    </interface>
    <disk type='file' device='disk' >
      <driver name='qemu' type='qcow2' />
      <source file='#{config['disk']}' />
      <target dev='hda' bus='virtio'/>
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
  begin 
      domain = @vmconn.lookup_domain_by_name(config['name'])
      domain.destroy
  rescue Libvirt::Error => e
      puts e.to_s + e.libvirt_message
  ensure
      if not domain.nil? then
          domain.undefine
      end
  end
  #ensure
      # Now define the VM
  # @domains[config['name']] = @vmconn.create_domain_linux(@sys_xmloutput)
      # and create and start the VM
  begin
      @vmconn.define_domain_xml(@sys_xmloutput)
  rescue Libvirt::DefinitionError => e
      puts "failed to define vm: " + e.libvirt_message
      raise
  end
      # query libvirt for the domain we just created
  begin
      @domains[config['name']] = @vmconn.lookup_domain_by_name(config['name'])
      @domains[config['name']].create()
  rescue Libvirt::Error => e
      puts e.to_s  + ": " + e.libvirt_message
  end
  #end
end


# sometimes we just need to know that the VM has been created...

# which server type are we looking at here?
Given /^that I want to confirm the server "([^"]*)" has been provisioned$/ do |serverType|
	# set the global to the value passed
	@serverType = serverType
end

# find out what we should be checking for
Then /^I should check the status of "([^"]*)" is "([^"]*)"$/ do |vm, requestedStatus|
  # retrieve the serverType info from cobbler
  serverName = @vm_config[vm]
  # Connect to libvirt and create a domain object based upon the "ci-build" hostname
  @ciDomain = @vmconn.lookup_domain_by_name(vm)

  curState = @ciDomain.info.state

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
Then /^I should ping the server "([^"]*)"$/ do |vm|
	# Set a counter so this script can bail if the build takes too long/fails to ping
	counter = 0
	# ping the value of the IP Address retrieved from the xml_description
	while Ping.pingecho(@vm_config[vm]['ip'])  == false do
		sleep(10)
		counter = counter +1
		puts "Counter currently at: #{counter}"
		raise ArgumentError, "It's taken over five minutes to try and ping this system, I'm bailing out now!" unless counter < 30
	end
	puts "I can ping the host! :)"
end

Then /^I should be able to connect to "([^"]*)" on port "([^"]*)"$/ do |vm, port|
	# Make sure the port checker doesn't time out
	ccounter = 0
	while is_port_open(@vm_config[vm]["ip"],port) == false do
		sleep(10)
		ccounter = ccounter + 1
		puts "Connection Counter currently at #{ccounter}"
		raise ArgumentError "No connection to port #{port} on this server after five minutes, bailing out now..." unless ccounter < 30
	end
end

# All the tests that we wanted to run are now complete, let's throw away the server so we know that we are always starting from a clean system next time.

# Which server do we want to destroy?
Given /^that I want to destroy the server "([^\"]*)"$/ do |name|
   @ciDomain = @vmconn.lookup_domain_by_name(name)
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

