package Rplus::Model::RealtyCategory::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::RealtyCategory;

sub object_class { 'Rplus::Model::RealtyCategory' }

__PACKAGE__->make_manager_methods('realty_categories');

1;

