package Rplus::Model::Landmark::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::Landmark;

sub object_class { 'Rplus::Model::Landmark' }

__PACKAGE__->make_manager_methods('landmarks');

1;

