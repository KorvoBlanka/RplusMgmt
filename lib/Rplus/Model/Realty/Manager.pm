package Rplus::Model::Realty::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::Realty;

sub object_class { 'Rplus::Model::Realty' }

__PACKAGE__->make_manager_methods('realty');

1;

