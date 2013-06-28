package TAEB::AI::Magus;
use Moose;
extends 'TAEB::AI';

sub next_action { TAEB::Action::Search->new(iterations => 1) }

1;

