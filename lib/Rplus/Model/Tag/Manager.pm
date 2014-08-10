package Rplus::Model::Tag::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::Tag;

sub object_class { 'Rplus::Model::Tag' }

__PACKAGE__->make_manager_methods('tags');

1;

