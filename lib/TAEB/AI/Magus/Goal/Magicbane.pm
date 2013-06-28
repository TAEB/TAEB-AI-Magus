package TAEB::AI::Magus::Goal::GetCrowned;
use Moose;
extends 'TAEB::AI::Magus::Goal';

sub prerequisite_goals { 'CoalignedAltar' }

1;

