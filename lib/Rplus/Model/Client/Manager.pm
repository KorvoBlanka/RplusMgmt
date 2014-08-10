package Rplus::Model::Client::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::Client;

sub object_class { 'Rplus::Model::Client' }

__PACKAGE__->make_manager_methods('clients');

1;

