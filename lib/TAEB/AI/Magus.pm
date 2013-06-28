package TAEB::AI::Magus;
use Moose;
extends 'TAEB::AI';

has manager => (
    is      => 'ro',
    isa     => 'TAEB::AI::Magus::GoalManager',
    default => sub { TAEB::AI::Magus::GoalManager->new },
    handles => 'current_goal',
);

sub next_action { TAEB::Action::Search->new(iterations => 1) }

1;

