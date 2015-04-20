package Rplus::Model::RealtyColorTag::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::RealtyColorTag;

sub object_class { 'Rplus::Model::RealtyColorTag' }

__PACKAGE__->make_manager_methods('realty_color_tags');

1;

