package TAEB::AI::Magus::Goal::CastleSmash;
use Moose;
extends 'TAEB::AI::Magus::Goal';

sub prerequisite_goals { 'FindTune' }

1;

