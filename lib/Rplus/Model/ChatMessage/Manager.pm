package Rplus::Model::ChatMessage::Manager;

use strict;

use base qw(Rose::DB::Object::Manager);

use Rplus::Model::ChatMessage;

sub object_class { 'Rplus::Model::ChatMessage' }

__PACKAGE__->make_manager_methods('chat_messages');

1;

