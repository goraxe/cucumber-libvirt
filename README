cucumber-libvirt
==============

This was forked from cucumber-vhost, the motivation was to reduce the reliance on cobbler as I use forman instead, and put together a vagrant like simple interface to libvirt.  

I have done some work with cucumber, vagrant, and puppet prior to this.  Over time I will merge the step definitions and abstract the vhost driver so that cukes can drive either drive vagrant or libvirt and not know nor care.  As such consider the interfaces here experimental and subject to change.  

Cucumber-libvirt should be able to drive multiple vm's out of the box, howeveer I have not yet tested this.

The software contained in this package are Copyright (c) 2012 Gordon Irving, 2010 Matthew Macdonald-Wallace, and are released under the GPL

"cucumber-libvirt" is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

"cucumber-libvirt" is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with cucumber-libvirt.  If not, see http://www.gnu.org/licenses/.

To configure the system, you will need to edit 'config.yml' and set it up for your network, currently each test needs a seperate config file to describe the vms required for the test.

TODO
====
- Move libvirt code into some form of lib
- Provide a multi vm example
- Add ability to mount host filesystem into guest tree



EXAMPLE 
=======

This script is the basis for launching a VM and checking that it is up
After that, it's all over to you! :)

An example that uses all of the steps that are currently available is below (Comments at the end of each line following a #), feel free to add extra steps...

Feature: Testing Vhosts
	This feature is to be used to create and manage vhosts



The code has been written to wait until the ping succeeds and the same is true for the port checker - if you need mroe flexibility than this, please feel free to fork and then merge back the changes!
