package Rplus::Model::ClientColorTag::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::ClientColorTag;

sub object_class { 'Rplus::Model::ClientColorTag' }

__PACKAGE__->make_manager_methods('client_color_tags');

1;

