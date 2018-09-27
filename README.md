# Rod Maneuvering

Prioritized Sweeping via Reinforcement Learning

Lua implementation is based on Sutton & Barto Book: "Reinforcement Learning: An Introduction". Bitmap file saving implementation is in pure Lua and is very slow but is used to draw graph for comparisions. Red-Black trees are used for the priority queue. To generate the videos below all the parameters are fixed to "n=32, Alpha=0.1, Gamma=0.97, Epsilon=0.1". Each frame is a policy drawn each time a new episodes finishes. At the end the policy found is drawn which in this case corresponds to the optimal one with 69 steps(found by a Breadth-First-Search for a static known precalculated environment).

The only tweak introduced to the algorithm in the book is that every 1000 episodes the epsilon is reduced otherwise no good covergence is found. Not sure while it won't work without that change.


![](Policy.gif)

![](Path.gif)

Below are some comparison charts for different parameters ranges. "Simulation Updates" states for n parameter. In each scenarion one of the parameter is allowed to take different values in a range while the others stay fixed to their original value.

![](RodManeuvering_SimUpdates.png)
![](RodManeuvering_Alpha.png)
![](RodManeuvering_Gamma.png)
![](RodManeuvering_Epsilon.png)
