package Rplus::Model::User::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::User;

sub object_class { 'Rplus::Model::User' }

__PACKAGE__->make_manager_methods('users');

1;

