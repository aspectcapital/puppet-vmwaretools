# Class: vmwaretools
#
# This class handles installing the VMware Tools Operating System Specific
# Packages.  http://packages.vmware.com/
#
# Parameters:
#
#   [*tools_version*]
#     The version of VMware Tools to install.
#     Default: 4.1latest
#
#   [*ensure*]
#     Ensure if present or absent.
#     Default: present
#
#   [*autoupgrade*]
#     Upgrade package automatically, if there is a newer version.
#     Default: false
#
#   [*package*]
#     Name of the package.
#     Only set this, if your platform is not supported or you know, what you're doing.
#     Default: auto-set, platform specific
#
#   [*service_ensure*]
#     Ensure if service is running or stopped
#     Default: running
#
#   [*service_name*]
#     Name of VMware Tools service
#     Only set this, if your platform is not supported or you know, what you're doing.
#     Default: auto-set, platform specific
#
#   [*service_enable*]
#     Start service at boot
#     Default: true
#
#   [*service_hasstatus*]
#     Service has status command
#     Default: true
#
#   [*service_hasrestart*]
#     Service has restart command
#     Default: true
#
# Actions:
#   Removes old VMwareTools package or runs vmware-uninstall-tools.pl if found.
#   Installs a vmware YUM repository, if needed.
#   Install the OSP or open vmware tools.
#   Starts the vmware-tools service.
#
# Requires:
#   Nothing
#
# Sample Usage:
#   class { vmwaretools':
#     tools_version = '4.0u3',
#   }
#
class vmwaretools (
  $tools_version      = '4.1latest',
  $ensure             = 'present',
  $autoupgrade        = false,
  $package            = $vmwaretools::params::package,
  $service_ensure     = 'running',
  $service_name       = $vmwaretools::params::service_name,
  $service_enable     = true,
  $service_hasstatus  = false,
  $service_hasrestart = true
) inherits vmwaretools::params {

  case $ensure {
    /(present)/: {
      if $autoupgrade == true {
        $package_ensure = 'latest'
      } else {
        $package_ensure = 'present'
      }

      if $service_ensure in [ running, stopped ] {
        $service_ensure_real = $service_ensure
      } else {
        fail('service_ensure parameter must be running or stopped')
      }
    }
    /(absent)/: {
      $package_ensure = 'absent'
      $service_ensure_real = 'stopped'
    }
    default: {
      fail('ensure parameter must be present or absent')
    }
  }

  case $::virtual {
    'vmware': {
      $service_pattern = $tools_version ? {
        /(4.1)/ => 'vmtoolsd',
        default => 'vmware-guestd',
      }

      $majdistrelease = regsubst($::operatingsystemrelease,'^(\d+)\.(\d+)','\1')

      # We use $::operatingsystem and not $::osfamily because certain things
      # (like Fedora) need to be excluded.
      case $::operatingsystem {
        'RedHat', 'CentOS', 'Scientific', 'SLC', 'Ascendos', 'PSBM', 'OracleLinux', 'OVS', 'OEL': {
          yumrepo { 'vmware-tools':
            descr    => "VMware Tools ${tools_version} - RHEL${majdistrelease} ${yum_basearch}",
            enabled  => 1,
            gpgcheck => 1,
            gpgkey   => "${vmwaretools::params::yum_server}${vmwaretools::params::yum_path}/VMWARE-PACKAGING-GPG-KEY.pub",
            baseurl  => "${vmwaretools::params::yum_server}${vmwaretools::params::yum_path}/esx/${tools_version}/rhel${majdistrelease}/${vmwaretools::params::yum_basearch}/",
            priority => $vmwaretools::params::yum_priority,
            protect  => $vmwaretools::params::yum_protect,
          }
        }

        'SLES', 'SLED', 'OpenSuSE', 'SuSE': {
          yumrepo { 'vmware-tools':
            descr    => "VMware Tools ${tools_version} - SUSE${majdistrelease} ${yum_basearch}",
            enabled  => 1,
            gpgcheck => 1,
            gpgkey   => "${vmwaretools::params::yum_server}${vmwaretools::params::yum_path}/VMWARE-PACKAGING-GPG-KEY.pub",
            baseurl  => "${vmwaretools::params::yum_server}${vmwaretools::params::yum_path}/esx/${tools_version}/suse${majdistrelease}/${vmwaretools::params::yum_basearch}/",
            priority => $vmwaretools::params::yum_priority,
            protect  => $vmwaretools::params::yum_protect,
          }
        }
      }

      package { 'VMwareTools':
        ensure => 'absent',
        before => Package['vmware-tools'],
      }

      exec { 'vmware-uninstall-tools':
        command => '/usr/bin/vmware-uninstall-tools.pl',
        path    => '/usr/bin:/usr/local/bin',
        onlyif  => 'test -f /usr/bin/vmware-uninstall-tools.pl',
        before  => [ Package['vmware-tools'], Package['VMwareTools'], ],
      }

      exec { 'vmware-uninstall-tools-local':
        command => '/usr/local/bin/vmware-uninstall-tools.pl',
        path    => '/usr/bin:/usr/local/bin',
        onlyif  => 'test -f /usr/local/bin/vmware-uninstall-tools.pl',
        before  => [ Package['vmware-tools'], Package['VMwareTools'], ],
      }

      # tools.syncTime = "FALSE" should be in the guest's vmx file and NTP
      # should be in use on the guest.  http://kb.vmware.com/kb/1006427
      # TODO: split vmware-tools.syncTime out to the NTP module??
      exec { 'vmware-tools.syncTime':
        command     => 'vmware-guestd --cmd "vmx.set_option synctime 1 0" || true',
        path        => '/usr/bin:/usr/local/bin',
        returns     => [ 0, 1, ],
        require     => Package['vmware-tools'],
        refreshonly => true,
      }

      package { 'vmware-tools':
        ensure  => $package_ensure,
        name    => $::operatingsystem ? {
          'Fedora' => 'open-vm-tools',
          default  => $package,
        },
        require => $::operatingsystem ? {
          'Fedora' => Package ['VMwareTools'],
          default  => [ Yumrepo['vmware-tools'], Package ['VMwareTools'], ],
        },
      }

      service { 'vmware-tools':
        name       => $service_name,
        ensure     => $service_ensure_real,
        enable     => $service_enable,
        hasrestart => $service_hasrestart,
        hasstatus  => false,
        pattern    => $service_pattern,
        require    => Package['vmware-tools'],
      }

    }
    # If we are not on VMware, do not do anything.
    default: { }
  }
}
