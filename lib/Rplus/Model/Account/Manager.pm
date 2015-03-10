package Rplus::Model::Account::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::Account;

sub object_class { 'Rplus::Model::Account' }

__PACKAGE__->make_manager_methods('accounts');

1;

