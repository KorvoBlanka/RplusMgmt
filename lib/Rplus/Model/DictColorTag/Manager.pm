package Rplus::Model::DictColorTag::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::DictColorTag;

sub object_class { 'Rplus::Model::DictColorTag' }

__PACKAGE__->make_manager_methods('dict_color_tags');

1;

